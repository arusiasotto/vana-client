//! Ops 0x26 / 0x27 (CMoPathDriveActorTask, FUN_1005e890 / FUN_1005e9c0 / FUN_1005eef0) and 0xa9 / 0xaa
//! (CMoActorRotationDriveTask, FUN_1005fa20 / FUN_1005fb30): an actor moved along a Vtx path or turned over an op's
//! duration, children of the scheduler task that started them (MODLOG "Ship actors").

use super::spline::{self, Seg};
use crate::dat::generator::KeyFrame;
use glam::Vec3;
use std::f32::consts::{FRAC_PI_2, PI, TAU};

/// What a frame's drives set on an actor: its position (+0xd4), its heading target (+0xe4), and the drawn heading
/// snapped to it too (+0x744 / +0x44).
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct ActorPose {
    pub pos: Option<Vec3>,
    pub target: Option<Vec3>,
    pub snap: Option<Vec3>,
}

/// FUN_10055ad0: the path drive's easing of u; 0 and 5 (no KeyFrame) are linear.
pub fn ease(u: f32, mode: u32) -> f32 {
    match mode {
        1 => (u * FRAC_PI_2).sin(),
        2 => 1.0 - (u * FRAC_PI_2).cos(),
        3 if u <= 0.5 => 0.5 * (u * PI).sin(),
        3 => 1.0 - 0.5 * (u * PI).sin(),
        4 => (1.0 - (u * PI).cos()) / 2.0,
        _ => u,
    }
}

fn wrap_pi(a: f32) -> f32 {
    (a + PI).rem_euclid(TAU) - PI
}

/// Ticks between the samples the facing is taken from: retail's frame at 30 fps *(ours: frame-rate independent)*.
const FACE_STEP: f32 = 2.0;

/// Op 0x26 (actor1) / 0x27 (actor2).
pub struct Drive {
    pub actor: u32,
    /// The scheduler task's uid: the drive dies with it.
    pub owner: u64,
    segs: Vec<Seg>,
    total: f32,
    left: f32,
    /// Flags @0x10: bit 0 absolute, bits 1..2 face (bit 1 of it: no pitch), bit 3 forward.
    abs: bool,
    face: u32,
    fwd: bool,
    yaw0: f32,
    curve: u32,
    key: Option<KeyFrame>,
    started: bool,
    turned: bool,
    /// The walk's ticks in the retail frame that made it (a relative drive's first step, below), and the time left
    /// where that first step ends (set on the first step).
    first: f32,
    base: Option<f32>,
    /// The last point applied (relative moves), and the facing's sample and ticks since it.
    last: Vec3,
    sample: Vec3,
    since: f32,
}

impl Drive {
    /// The op's fields: i16 @6 duration (x speed, cut to whole ticks: __ftol at 0x1005cad3), u32 @0x10 flags, u32
    /// @0x14 curve, f32 @0x18 yaw0; `over` is the fast-forward's overshoot (DAT_1047bf14), taken off the time left.
    /// `first`: the retail frame's ticks of the walk that made it.
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        actor: u32,
        owner: u64,
        segs: Vec<Seg>,
        raw: &[u8],
        speed: f32,
        over: f32,
        key: Option<KeyFrame>,
        first: f32,
    ) -> Self {
        let u32_at = |o: usize| raw.get(o..o + 4).map_or(0, |b| u32::from_le_bytes(b.try_into().unwrap()));
        let dur = raw.get(6..8).map_or(0, |b| i16::from_le_bytes([b[0], b[1]]));
        let flags = u32_at(0x10);
        let total = (dur as f32 * speed).trunc();
        Self {
            actor,
            owner,
            segs,
            total,
            left: total - over,
            abs: flags & 1 != 0,
            face: flags >> 1 & 3,
            fwd: flags & 8 != 0,
            yaw0: f32::from_bits(u32_at(0x18)),
            curve: u32_at(0x14).min(5),
            key,
            started: false,
            turned: false,
            first: first.max(0.0),
            base: None,
            last: Vec3::ZERO,
            sample: Vec3::ZERO,
            since: 0.0,
        }
    }

    fn at(&self, u: f32) -> Vec3 {
        spline::eval(&self.segs, u)
    }

    /// The path's point with `left` ticks to go: u by the time, its direction, then the curve.
    fn point(&self, left: f32) -> Vec3 {
        let u = if self.total > 0.0 { left / self.total } else { 0.0 };
        let u = if self.fwd { 1.0 - u } else { u };
        let f = match (&self.key, self.curve) {
            (_, c) if c < 5 => ease(u, c),
            (Some(k), _) => k.linear(u),
            _ => u,
        };
        self.at(f)
    }

    /// One frame of `dt` ticks, the actor at `pos` turned `rot` now: what it sets, and whether it goes on. The end
    /// (time below 0) writes the point at u = 1.0 whatever the direction (0x1005ea0b) and deletes the drive, whose
    /// destructor lets the actor go (FUN_1005f2c0 -> vt +0x17c clears +0x88 bit 0). The actor's next update
    /// (FUN_100a57f0) then finds bit 0 clear and takes its position from +0x34 (FUN_10086e90 copies it to +0xc4) and
    /// its heading target from +0x44, both as its last update left them, so that point and the heading toward it
    /// never show: the actor stays where the drive's last running frame put it. Only a first facing (+0xa3 clear)
    /// stays, since it is written to the drawn rotation itself (+0x744 / +0x44). The frame it is made in counts: the task list puts
    /// a new task straight after the running one and walks it next (FUN_100750b0 sets the walk's next, +0xd5c), and
    /// FUN_1005e9c0 takes the frame's ticks off before anything else.
    ///
    /// A relative drive's first update moves nothing and keeps the point it reached as the one later moves start
    /// from, so the first retail frame's stretch of the path never shows. That frame is the walk's ticks (`first`),
    /// whatever our own frames are: until the time passes it the actor stays, and the moves start from its point.
    pub fn step(&mut self, dt: f32, pos: Vec3, rot: Vec3) -> (ActorPose, bool) {
        if self.base.is_none() {
            let base = (self.left - self.first).max(0.0);
            (self.base, self.last) = (Some(base), self.point(base));
        }
        self.left -= dt;
        if self.left >= 0.0 {
            let pose = self.apply(self.point(self.left), dt, pos, rot);
            self.started = true;
            (pose, true)
        } else if self.started {
            let snap = self.apply(self.at(1.0), dt, pos, rot).snap;
            (ActorPose { snap, ..Default::default() }, false)
        } else {
            (ActorPose::default(), false)
        }
    }

    fn apply(&mut self, p: Vec3, dt: f32, pos: Vec3, rot: Vec3) -> ActorPose {
        let mut out = ActorPose::default();
        if self.abs {
            out.pos = Some(p);
        } else if self.base.is_some_and(|b| self.left <= b) {
            out.pos = Some(pos + (p - self.last));
            self.last = p;
        }
        if self.face == 0 {
            return out;
        }
        if !self.started {
            (self.sample, self.since) = (p, 0.0);
            return out;
        }
        self.since += dt;
        if self.since < FACE_STEP {
            return out;
        }
        let d = p - self.sample;
        (self.sample, self.since) = (p, 0.0);
        let h = (d.x * d.x + d.z * d.z).sqrt();
        let yaw = wrap_pi(self.yaw0 - d.z.atan2(d.x));
        // Face 2 / 3 leave retail's pitch uninitialised (no file uses them): ours keeps it *(inf)*.
        let pitch = if self.face & 2 == 0 { d.y.atan2(h) } else { rot.z };
        let r = Vec3::new(0.0, yaw, pitch);
        if !self.turned {
            self.turned = true;
            out.snap = Some(r);
        } else if h >= 0.1 {
            out.target = Some(r);
        }
        out
    }
}

/// Op 0xa9 (actor1) / 0xaa (actor2): f32 @8 / @0xc / @0x10 the target in degrees, u8 @0x14 the mode, i16 @6 the
/// duration (x speed); the start is the actor's drawn rotation.
pub struct RotDrive {
    pub actor: u32,
    pub owner: u64,
    start: Vec3,
    target: Vec3,
    mode: u8,
    total: f32,
    left: f32,
}

impl RotDrive {
    pub fn new(actor: u32, owner: u64, raw: &[u8], speed: f32, start: Vec3) -> Self {
        let f = |o: usize| raw.get(o..o + 4).map_or(0.0, |b| f32::from_le_bytes(b.try_into().unwrap()));
        let dur = raw.get(6..8).map_or(0, |b| i16::from_le_bytes([b[0], b[1]]));
        let total = dur as f32 * speed;
        Self {
            actor,
            owner,
            start,
            target: Vec3::new(f(8), f(0xc), f(0x10)) * (PI / 180.0),
            mode: raw.get(0x14).copied().unwrap_or(0),
            total,
            left: total,
        }
    }

    /// Mode 0 holds the target every frame until its scheduler ends; the others turn linearly (no wrap) and end
    /// after the frame they reach it.
    pub fn step(&mut self, dt: f32) -> (ActorPose, bool) {
        if self.mode == 0 {
            return (ActorPose { snap: Some(self.target), ..Default::default() }, true);
        }
        self.left -= dt;
        let k = if self.left >= 0.0 && self.total > 0.0 { 1.0 - self.left / self.total } else { 1.0 };
        let r = self.start + (self.target - self.start) * k;
        (ActorPose { target: Some(r), ..Default::default() }, self.left >= 0.0)
    }
}

/// Scheduler op 0x62: actor1 turns toward actor2 by `rate` radians a retail frame (2 ticks) until it has turned
/// `remaining` (drawobj +0x870 / +0x874, stepped in FUN_100c6290 while +0x86c counts a live timer task), the timer being
/// dur x speed ticks (FUN_10060f80 / FUN_10060fd0).
pub struct FaceDrive {
    pub actor: u32,
    rot: Vec3,
    remaining: f32,
    rate: f32,
    left: f32,
    acc: f32,
}

impl FaceDrive {
    /// `from` / `to` the two actors' positions, `rot` actor1's drawn rotation, `deg` f32 @8 (degrees a frame).
    pub fn new(actor: u32, from: Vec3, to: Vec3, rot: Vec3, deg: f32, ticks: f32) -> Self {
        let (mut dx, mut dz) = (to.x - from.x, to.z - from.z);
        // As coded: a signed test, not a distance.
        if dx < 0.1 && dz < 0.1 {
            (dx, dz) = (1.0, 0.0);
        }
        let mut d = -dz.atan2(dx) - rot.y;
        if d > PI {
            d -= 2.0 * PI;
        }
        if d < -PI {
            d += 2.0 * PI;
        }
        let rate = deg * (PI / 180.0);
        Self { actor, rot, remaining: d.abs(), rate: if d < 0.0 { -rate } else { rate }, left: ticks, acc: 0.0 }
    }

    /// One frame of `dt` ticks: the pose, and whether the timer still runs.
    pub fn step(&mut self, dt: f32) -> (ActorPose, bool) {
        self.left -= dt;
        self.acc += dt;
        while self.acc >= 2.0 && self.remaining > 0.0 {
            self.acc -= 2.0;
            self.rot.y = wrap_pi(self.rot.y + self.rate);
            let rest = self.remaining - self.rate.abs();
            if rest < 0.0 {
                self.rot.y = wrap_pi(self.rot.y + if self.rate > 0.0 { rest } else { -rest });
                self.remaining = 0.0;
            } else {
                self.remaining = rest;
            }
        }
        (ActorPose { target: Some(self.rot), ..Default::default() }, self.left >= 0.0)
    }
}

/// The Vtx segments of a path, None below two points.
pub fn path(vtx: &[u8]) -> Option<Vec<Seg>> {
    spline::build(&spline::points(vtx))
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Op 0x62: 10 degrees a 2-tick frame toward a target a quarter turn away; it stops on the heading, and the
    /// timer ends it.
    #[test]
    fn face_drive_turns_to_the_target() {
        let mut d = FaceDrive::new(1, Vec3::ZERO, Vec3::new(0.0, 0.0, 5.0), Vec3::ZERO, 10.0, 40.0);
        let (p, more) = d.step(2.0);
        assert!(more && (p.target.unwrap().y + 10f32.to_radians()).abs() < 1e-5, "{:?}", p.target);
        let mut last = None;
        for _ in 0..19 {
            last = Some(d.step(2.0));
        }
        let (p, more) = last.unwrap();
        assert!((p.target.unwrap().y + FRAC_PI_2).abs() < 1e-4, "{:?}", p.target);
        // At 0 ticks left the timer still runs (FUN_10060fd0 ends below 0).
        assert!(more && !d.step(2.0).1);
    }

    /// 0x1005ea0b + FUN_100a57f0: the frame a drive's time goes below 0 sets no position and no heading target,
    /// backward (flags 1) or forward (flags 9); the frame before is the path's end for its direction.
    #[test]
    fn end_sets_no_position() {
        let pts = [Vec3::ZERO, Vec3::new(10.0, 0.0, 0.0), Vec3::new(20.0, 0.0, 5.0)];
        for (flags, end) in [(1u32, pts[0]), (9, pts[2]), (3, pts[0]), (0xb, pts[2])] {
            let mut raw = [0u8; 0x1c];
            raw[6..8].copy_from_slice(&10i16.to_le_bytes());
            raw[0x10..0x14].copy_from_slice(&flags.to_le_bytes());
            let mut d = Drive::new(1, 1, spline::build(&pts).unwrap(), &raw, 1.0, 0.0, None, 2.0);
            let mut last = ActorPose::default();
            for _ in 0..5 {
                let (p, on) = d.step(2.0, Vec3::ZERO, Vec3::ZERO);
                assert!(on);
                last = p;
            }
            assert!(last.pos.unwrap().distance(end) < 1e-4, "flags {flags}: {:?}", last.pos);
            assert_eq!(d.step(2.0, Vec3::ZERO, Vec3::ZERO), (ActorPose::default(), false), "flags {flags}");
        }
    }

    /// A relative drive (flags bit 0 clear) ends at the same place at 30 fps and at 240 (quarter ticks, exact in f32): the first retail frame's
    /// stretch (the walk's 2 ticks) is skipped either way, not just our first frame's.
    #[test]
    fn relative_first_frame_is_the_walks() {
        let pts = [Vec3::ZERO, Vec3::new(10.0, 0.0, 0.0), Vec3::new(20.0, 0.0, 5.0)];
        let run = |dt: f32| {
            let mut raw = [0u8; 0x1c];
            raw[6..8].copy_from_slice(&40i16.to_le_bytes());
            raw[0x10..0x14].copy_from_slice(&8u32.to_le_bytes());
            let mut d = Drive::new(1, 1, spline::build(&pts).unwrap(), &raw, 1.0, 0.0, None, 2.0);
            let mut pos = Vec3::new(100.0, 0.0, 0.0);
            while let (p, true) = d.step(dt, pos, Vec3::ZERO) {
                pos = p.pos.unwrap_or(pos);
            }
            pos
        };
        let (thirty, fast) = (run(2.0), run(0.25));
        assert!(thirty.distance(fast) < 1e-3, "30 fps {thirty}, 300 fps {fast}");
        // Retail moves it the path's end less its first 2 ticks.
        assert!(thirty.x > 100.0 && thirty.distance(Vec3::new(100.0, 0.0, 0.0) + pts[2]) > 0.1, "{thirty}");
    }

    /// The curves at f(0.25) for modes 0..4 (MODLOG "Ship actors"); the ends.
    #[test]
    fn curves() {
        for (m, want) in [(0, 0.25), (1, 0.382_683), (2, 0.076_120), (3, 0.353_553), (4, 0.146_447)] {
            assert!((ease(0.25, m) - want).abs() < 1e-5, "mode {m}: {}", ease(0.25, m));
            assert!(ease(0.0, m).abs() < 1e-6 && (ease(1.0, m) - 1.0).abs() < 1e-6, "mode {m} ends");
        }
    }
}
