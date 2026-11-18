//! The model's motion queues as FFXiMain keeps them (30261102_0):
//! seven body regions, each a list of weighted entries, oldest first. A new motion is appended to the regions
//! it has chunks for, fades in over its blend and starts the fade-out of the entry before it; the poser walks
//! each region oldest to newest and blends each entry over the ones before by its weight (FUN_1001a420).
//!
//! Times are 1/60 s ticks, positions are frames (a frame is ticks x speed x 0.5 at rate 1).

/// Regions 0..4 pose the body (higher ones win a bone); 5 and 6 are overlays blended over it by the region weight.
pub const REGIONS: usize = 7;
/// The eyes (a blink), the mouth (a line's face motion), the overlay a reaction or moving guard plays in, and the
/// overlay a `mou6` talk plays in.
pub const EYES: usize = 3;
pub const MOUTH: usize = 4;
pub const OVERLAY: usize = 5;
pub const OVERLAY_TALK: usize = 6;

/// Entry state (+8): playing, fading in, fading out, fading in while already on its way out.
pub const PLAYING: u8 = 0;
pub const FADE_IN: u8 = 1;
pub const FADE_OUT: u8 = 2;
pub const FADE_BOTH: u8 = 3;

/// One queued chunk (FUN_1001a800's 0x40-byte entry). `anim` is the caller's handle of the chunk; `frames` and
/// `speed` are the chunk's (resource +0x34 / +0x36).
#[derive(Clone, Debug, PartialEq)]
pub struct Entry<A> {
    pub anim: A,
    pub frames: f32,
    pub speed: f32,
    /// +8.
    pub state: u8,
    /// +0xc: ticks left once fading out.
    pub out: f32,
    /// +0x10.
    pub weight: f32,
    /// +0x14: blend-in ticks left.
    pub blend: f32,
    /// +0x18: weight per tick while fading in (negative after a counted end in regions 3 and up).
    pub slope: f32,
    /// +0x1c: the entry's share of an overlay region's weight.
    pub share: f32,
    /// +0x20: the fade-out length a counted end uses, and the blend back to the status motion.
    pub out_len: f32,
    /// +0x24.
    pub frame: f32,
    /// +0x28.
    pub rate: f32,
    /// +0x2c: 0 loops, n plays n times, -1 has finished.
    pub count: i32,
    /// +0x38: the frame it ends at when above 0, else the chunk's frame count.
    pub end: f32,
    /// Ours: ticks toward the next whole-frame step of a two-frame chunk (see `advance`).
    pub flip: f32,
}

/// FUN_1001ad00's arguments after the resource.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Enq {
    pub share: f32,
    pub rate: f32,
    pub count: u8,
    pub blend: f32,
    pub out_len: f32,
    pub start: f32,
    pub end: f32,
    /// FUN_1001a6e0: the start frame carries the phase of the region's last entry. Without it (FUN_1001a660 ->
    /// FUN_1001acb0) the start frame is `start`.
    pub carry: bool,
}

impl Enq {
    /// A looping status motion (FUN_100c83c0): share 1, out 1.
    pub fn status(rate: f32, blend: f32, carry: bool) -> Enq {
        Enq { share: 1.0, rate, count: 0, blend, out_len: 1.0, start: 0.0, end: 0.0, carry }
    }
}

impl<A> Entry<A> {
    /// FUN_1001b520: the fade-out starts, over `ticks`.
    pub fn fade(&mut self, ticks: f32) {
        match self.state {
            PLAYING => {
                self.state = FADE_OUT;
                self.out = ticks;
            }
            FADE_IN => {
                self.state = FADE_BOTH;
                self.blend = ticks;
                self.out = ticks;
            }
            _ if ticks <= 1.0 => {
                self.out = 0.0;
                self.state = FADE_OUT;
            }
            _ => {}
        }
    }

    /// FUN_1001b590: a counted motion of regions 3 and up ended; its weight runs down over `out_len`.
    fn end_fade(&mut self) {
        if matches!(self.state, PLAYING | FADE_IN) {
            let f = self.out_len;
            self.blend = f;
            self.out = f;
            self.slope = if f <= 0.0 { 0.0 } else { -(self.weight / f) };
            self.state = FADE_BOTH;
        }
    }

    /// FUN_1001b5d0: one fade step; false when the entry's time is up.
    fn fade_step(&mut self, dt: f32) -> bool {
        match self.state {
            FADE_IN => {
                self.weight += dt * self.slope;
                self.blend -= dt;
                if self.blend <= 0.0 {
                    self.state = PLAYING;
                }
            }
            FADE_OUT => {
                self.out -= dt;
                if self.out <= 0.0 {
                    return false;
                }
            }
            FADE_BOTH => {
                self.weight += dt * self.slope;
                self.blend -= dt;
                self.out -= dt;
                if self.out <= 0.0 {
                    self.state = FADE_OUT;
                    self.weight = self.weight.min(1.0);
                    return false;
                }
                if self.blend <= 0.0 {
                    self.state = FADE_OUT;
                }
            }
            _ => {}
        }
        self.weight = self.weight.clamp(0.0, 1.0);
        true
    }

    /// FUN_1001a8e0: the frame advances; true when a counted play just ended.
    fn advance(&mut self, dt: f32) -> bool {
        if self.count < 0 {
            return false;
        }
        let before = self.frame;
        let end = if self.end > 0.0 { self.end } else { self.frames };
        let step = self.speed * 0.5;
        // A two-frame chunk at speed 1 steps a whole frame a tick call, whatever the tick's length: once a frame at
        // retail's 30 fps. Ours steps it every 2 ticks, so a bee's wings beat as retail's at any frame rate.
        self.frame = if end == 2.0 && step == 0.5 {
            self.flip += dt;
            let steps = (self.flip / 2.0).floor();
            self.flip -= steps * 2.0;
            self.frame + steps
        } else {
            self.frame + dt * step * self.rate
        };
        let over = self.frame >= end;
        if !over && self.frame >= 0.0 {
            return false;
        }
        if self.count > 0 {
            self.count -= 1;
            if self.count == 0 {
                self.count = -1;
                self.rate = 0.0;
                self.frame = before;
                return true;
            }
        }
        if over {
            if end <= 0.0 {
                self.frame = 0.0;
            } else {
                while self.frame >= end {
                    self.frame -= end;
                }
            }
        } else if end <= 0.0 {
            self.frame = 1.0;
        } else {
            while self.frame < 0.0 {
                self.frame += end;
            }
        }
        false
    }
}

/// FUN_1001ad00's phase carry: the frame a new chunk starts at in a region whose last entry stands at `at` (frames)
/// of a chunk `old` (frames, speed): the same fraction of its cycle, pushed on by half the blend at the new rate.
pub fn carry(at: f32, old: (f32, f32), new: (f32, f32), rate: f32, blend: f32) -> f32 {
    let old_len = old.0 / old.1;
    let new_len = new.0 / new.1;
    let (mut pos, mut extra) = (0.0, 0.0);
    if old_len > 0.001 {
        let k = 1.0 / old_len;
        pos = at * k;
        extra = new.1 * 0.5 * k * new_len * rate * blend;
    }
    let mut pos = pos * new_len + extra;
    if new_len <= 0.0 {
        pos = 0.0;
    } else {
        while pos >= new_len {
            pos -= new_len;
        }
    }
    new.1 * pos
}

/// One entry as the poser takes it: `start` opens a region (the first entry posed in it sets its bones outright, the
/// following blend over by `weight`); `over` is 0 for the body regions, 1 / 2 for the overlay regions 5 / 6.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Layer<A> {
    pub anim: A,
    pub frame: f32,
    pub weight: f32,
    pub start: bool,
    pub over: u8,
    pub region: u8,
}

/// The seven region queues of one model and its "counted motion ended" flag (model +0x79c, vtable +0x1fc / +0x200).
#[derive(Clone, Debug)]
pub struct Queues<A> {
    pub regions: [Vec<Entry<A>>; REGIONS],
    pub done: bool,
}

impl<A> Default for Queues<A> {
    fn default() -> Self {
        Queues { regions: Default::default(), done: false }
    }
}

impl<A: Clone> Queues<A> {
    /// FUN_1001a660 / FUN_1001a6e0 -> FUN_1001ad00: `anim` (a chunk of `frames` at `speed`) joins `region`.
    pub fn enqueue(&mut self, region: usize, anim: A, frames: f32, speed: f32, e: &Enq) {
        let Some(list) = self.regions.get_mut(region) else { return };
        let blend = if e.blend == 0.0 { 1.0 } else { e.blend };
        let mut n = Entry {
            anim,
            frames,
            speed,
            state: FADE_IN,
            out: 0.0,
            weight: 0.0,
            blend,
            slope: 1.0 / blend,
            share: e.share,
            out_len: if e.out_len < 0.0 { 1.0 } else { e.out_len },
            frame: e.start,
            rate: e.rate,
            count: e.count as i32,
            end: e.end,
            flip: 0.0,
        };
        if let Some(l) = list.last_mut() {
            n.frame = carry(l.frame, (l.frames, l.speed), (frames, speed), e.rate, blend);
            // FUN_1001acb0 puts the given start back.
            if !e.carry {
                n.frame = e.start;
            }
            l.fade(blend);
        }
        list.push(n);
        // More than three: the oldest extras go within a tick. The oldest one left stands at full weight.
        let extra = list.len().saturating_sub(3);
        for x in &mut list[..extra] {
            x.fade(1.0);
        }
        list[extra].weight = 1.0;
        if region == 0 {
            self.done = false;
        }
    }

    /// FUN_100cd920 / FUN_100cd540 for one motion: `chunks` are its (region, chunk, frames, speed) in search order.
    /// A `region` argument of 5 or 6 puts every chunk there; one chunk per region is taken. When region 0 took one,
    /// the regions 0..2 that held a finished counted motion and got nothing are emptied. Returns the regions queued.
    pub fn enqueue_motion(
        &mut self,
        chunks: impl IntoIterator<Item = (u8, A, f32, f32)>,
        region: u8,
        e: &Enq,
        mut rate_of: impl FnMut(u8) -> f32,
    ) -> u8 {
        let finished: [bool; 3] = std::array::from_fn(|r| self.finished(r));
        let mut mask = 0u8;
        for (r, anim, frames, speed) in chunks {
            let r = if region >= 5 { region } else { r };
            if r as usize >= REGIONS || mask >> r & 1 != 0 {
                continue;
            }
            self.enqueue(r as usize, anim, frames, speed, &Enq { rate: rate_of(r), ..*e });
            mask |= 1 << r;
        }
        if mask & 1 != 0 {
            for r in 0..3 {
                if finished[r] && mask >> r & 1 == 0 {
                    self.regions[r].clear();
                }
            }
        }
        mask
    }

    /// FUN_1001b360: the region holds a finished counted motion.
    pub fn finished(&self, region: usize) -> bool {
        self.regions[region].iter().any(|e| e.count < 0)
    }

    /// FUN_1001b170: every entry of the region starts its fade-out over `ticks`.
    pub fn fade_region(&mut self, region: usize, ticks: f32) {
        for e in &mut self.regions[region] {
            e.fade(ticks);
        }
    }

    /// FUN_100c83c0's rate change: the newest entry of every region.
    pub fn set_rate(&mut self, rate: f32) {
        for e in self.regions.iter_mut().filter_map(|l| l.last_mut()) {
            e.rate = rate;
        }
    }

    /// FUN_100d4b20: the blend back to the status motion after a counted one: the longer out length of the newest
    /// entries of regions 0 and 1 (4.0 with neither).
    pub fn back_blend(&self) -> f32 {
        match (self.regions[0].last(), self.regions[1].last()) {
            (Some(a), Some(b)) => a.out_len.max(b.out_len),
            (Some(a), None) | (None, Some(a)) => a.out_len,
            (None, None) => 4.0,
        }
    }

    /// FUN_1001a3e0: a frame of `dt` ticks; regions 6 down to 0, fades first, then the frames.
    pub fn tick(&mut self, dt: f32) {
        for r in (0..REGIONS).rev() {
            let list = &mut self.regions[r];
            let mut i = 0;
            while i < list.len() {
                if list[i].fade_step(dt) {
                    i += 1;
                } else if i + 1 == list.len() && r < 3 {
                    // The last entry of a body region stays; the model is told its motion is over.
                    self.done = true;
                    break;
                } else {
                    list.remove(i);
                }
            }
            let n = list.len();
            for (i, e) in list.iter_mut().enumerate() {
                if e.advance(dt) {
                    if r >= 3 {
                        e.end_fade();
                    } else if i + 1 == n {
                        self.done = true;
                    }
                }
            }
        }
    }

    /// FUN_1001a420 / FUN_1001b230: the entries to pose, in order, and the weights of the overlay regions 5 and 6.
    /// Regions 4 down to 0 (a bone a higher region wrote is taken), then 5 and 6; an entry is left out when the one
    /// after it stands at full weight, or its weight is under 1e-4.
    pub fn layers(&self, out: &mut Vec<Layer<A>>) -> [f32; 2] {
        out.clear();
        let mut over = [0.0f32; 2];
        for r in (0..5).chain(5..REGIONS).map(|k| if k < 5 { 4 - k } else { k }) {
            let list = &self.regions[r];
            let mut start = true;
            let mut acc = 0.0;
            for (i, e) in list.iter().enumerate() {
                acc = e.share * e.weight + (1.0 - e.weight) * acc;
                if list.get(i + 1).is_some_and(|n| n.weight == 1.0) {
                    continue;
                }
                // The first entry of an overlay region poses at full weight.
                let weight = if i == 0 && r > 4 { 1.0 } else { e.weight };
                if weight < 1e-4 {
                    continue;
                }
                out.push(Layer {
                    anim: e.anim.clone(),
                    frame: e.frame,
                    weight,
                    start,
                    over: r.saturating_sub(4) as u8,
                    region: r as u8,
                });
                start = false;
            }
            if r > 4 {
                over[r - 5] = acc;
            }
        }
        over
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn q() -> Queues<u32> {
        Queues::default()
    }

    /// FUN_1001ad00: half way through a 40-frame cycle at speed 1, a 20-frame cycle starts half way through its cycle,
    /// plus half the 16-tick blend at the new rate (0.5 frames a tick x 16 / 2 = 4 frames): frame 14.
    #[test]
    fn carry_keeps_the_fraction() {
        assert!((carry(20.0, (40.0, 1.0), (20.0, 1.0), 1.0, 16.0) - 14.0).abs() < 1e-4);
        // Past the end it wraps; an old chunk of no length starts at 0.
        assert!((carry(38.0, (40.0, 1.0), (20.0, 1.0), 1.0, 16.0) - 3.0).abs() < 1e-4);
        assert_eq!(carry(5.0, (0.0, 1.0), (20.0, 1.0), 1.0, 16.0), 0.0);
        // Speed 2: the lengths are frames / speed but the old position is taken in frames as it is (vtable +0x30
        // returns +0x24), so a quarter of the old cycle (frame 10 of 40) lands on half of the new one.
        assert!((carry(10.0, (40.0, 2.0), (20.0, 2.0), 1.0, 0.0) - 10.0).abs() < 1e-4);
    }

    /// Row 9: each region carries its phase. The legs (region 0) stand at frame 30 of 40 and the upper body
    /// (region 1) at frame 5 of 40 when a 20-frame motion is queued in both.
    #[test]
    fn phase_is_per_region() {
        let mut m = q();
        m.enqueue_motion([(0, 1, 40.0, 1.0), (1, 2, 40.0, 1.0)], 0, &Enq::status(1.0, 16.0, true), |_| 1.0);
        m.regions[0][0].frame = 30.0;
        m.regions[1][0].frame = 5.0;
        m.enqueue_motion([(0, 3, 20.0, 1.0), (1, 4, 20.0, 1.0)], 0, &Enq::status(1.0, 16.0, true), |_| 1.0);
        assert!((m.regions[0][1].frame - 19.0).abs() < 1e-4, "{}", m.regions[0][1].frame);
        assert!((m.regions[1][1].frame - 6.5).abs() < 1e-4, "{}", m.regions[1][1].frame);
        // The old entries fade out over the blend, at full weight under the new ones.
        assert_eq!((m.regions[0][0].state, m.regions[0][0].out, m.regions[0][0].weight), (FADE_BOTH, 16.0, 1.0));
        // Without the carry (FUN_1001acb0) the start is the one given.
        m.enqueue(0, 5, 20.0, 1.0, &Enq { carry: false, start: 3.0, ..Enq::status(1.0, 16.0, false) });
        assert_eq!(m.regions[0][2].frame, 3.0);
    }

    /// A new entry's weight runs 0 -> 1 over its blend; the one before is dropped when its out timer ends.
    #[test]
    fn blend_in_and_out() {
        let mut m = q();
        m.enqueue(0, 1, 40.0, 1.0, &Enq::status(1.0, 16.0, true));
        assert_eq!(m.regions[0][0].weight, 1.0, "the oldest entry stands at full weight");
        for _ in 0..16 {
            m.tick(1.0);
        }
        assert_eq!(m.regions[0][0].state, PLAYING);
        m.enqueue(0, 2, 40.0, 1.0, &Enq::status(1.0, 16.0, true));
        for _ in 0..8 {
            m.tick(1.0);
        }
        assert_eq!(m.regions[0].len(), 2);
        assert!((m.regions[0][1].weight - 0.5).abs() < 1e-4);
        let mut l = Vec::new();
        m.layers(&mut l);
        assert_eq!(l.iter().map(|x| (x.anim, x.start)).collect::<Vec<_>>(), [(1, true), (2, false)]);
        for _ in 0..8 {
            m.tick(1.0);
        }
        assert_eq!(m.regions[0].len(), 1);
        assert_eq!((m.regions[0][0].anim, m.regions[0][0].weight, m.regions[0][0].state), (2, 1.0, PLAYING));
    }

    /// More than three entries: the oldest extras get a one-tick fade and the oldest kept one full weight.
    #[test]
    fn fourth_entry_fast_fades_the_oldest() {
        let mut m = q();
        for a in 1..=4 {
            m.enqueue(0, a, 40.0, 1.0, &Enq::status(1.0, 16.0, true));
        }
        let l = &m.regions[0];
        assert_eq!(l.len(), 4);
        assert_eq!((l[0].state, l[0].out), (FADE_OUT, 0.0), "already fading: its time is cut to nothing");
        assert_eq!(l[1].weight, 1.0);
        m.tick(1.0);
        assert_eq!(m.regions[0].iter().map(|e| e.anim).collect::<Vec<_>>(), [2, 3, 4]);
    }

    /// A counted motion in a body region holds the frame before its end and raises the flag; a region-0 enqueue
    /// clears it, and the regions that held a finished motion and got nothing are emptied.
    #[test]
    fn counted_end_holds_and_flags() {
        let mut m = q();
        m.enqueue_motion([(0, 1, 40.0, 1.0), (1, 2, 40.0, 1.0)], 0, &Enq::status(1.0, 16.0, true), |_| 1.0);
        let swing =
            Enq { share: 1.0, rate: 1.0, count: 1, blend: 4.0, out_len: 10.0, start: 0.0, end: 0.0, carry: false };
        m.enqueue_motion([(1, 3, 10.0, 1.0)], 0, &swing, |_| 1.0);
        assert!(!m.done);
        for _ in 0..19 {
            m.tick(1.0);
        }
        assert!(!m.done);
        m.tick(1.0);
        m.tick(1.0);
        assert!(m.done);
        let e = m.regions[1].last().unwrap();
        assert_eq!((e.count, e.rate), (-1, 0.0));
        assert!(e.frame < 10.0 && e.frame >= 9.0);
        assert_eq!(m.back_blend(), 10.0);
        // The status motion comes back in region 0 only: region 1's finished swing is dropped.
        m.enqueue_motion([(0, 1, 40.0, 1.0)], 0, &Enq::status(1.0, 10.0, false), |_| 1.0);
        assert!(!m.done);
        assert!(m.regions[1].is_empty());
    }

    /// A blend of 0 counts as 1 tick (0x1001ad77) in the new entry, the phase carry and the old entry's fade alike, so
    /// at a fraction of a tick both are still posed.
    #[test]
    fn blend_zero_is_one_tick() {
        let mut m = q();
        m.enqueue(0, 1, 40.0, 1.0, &Enq::status(1.0, 16.0, true));
        for _ in 0..16 {
            m.tick(1.0);
        }
        m.regions[0][0].frame = 20.0;
        m.enqueue(0, 2, 20.0, 1.0, &Enq::status(1.0, 0.0, true));
        // Half of the 20-frame cycle, plus half a tick at rate 1 (0.25 frames).
        assert!((m.regions[0][1].frame - 10.25).abs() < 1e-4, "{}", m.regions[0][1].frame);
        m.tick(0.2);
        assert_eq!(m.regions[0].len(), 2, "the old entry stays for its one tick");
        assert!((m.regions[0][1].weight - 0.2).abs() < 1e-4);
    }

    /// Region 5 or 6 given: every chunk goes there and only the first is taken (a reaction, a moving guard).
    #[test]
    fn overlay_region_takes_one_chunk() {
        let mut m = q();
        let e = Enq { share: 1.0, rate: 1.0, count: 1, blend: 2.0, out_len: 4.0, start: 0.0, end: 0.0, carry: false };
        let mask = m.enqueue_motion([(0, 1, 10.0, 1.0), (1, 2, 10.0, 1.0)], 5, &e, |_| 1.0);
        assert_eq!(mask, 1 << 5);
        assert_eq!(m.regions[5].iter().map(|x| x.anim).collect::<Vec<_>>(), [1]);
        assert!(m.regions[..5].iter().all(|l| l.is_empty()));
    }

    /// A motion that does not take region 0 leaves the regions holding a finished counted motion as they are.
    #[test]
    fn finished_regions_kept_without_region_0() {
        let mut m = q();
        m.enqueue_motion([(0, 1, 40.0, 1.0), (1, 2, 40.0, 1.0)], 0, &Enq::status(1.0, 16.0, true), |_| 1.0);
        let swing =
            Enq { share: 1.0, rate: 1.0, count: 1, blend: 4.0, out_len: 10.0, start: 0.0, end: 0.0, carry: false };
        m.enqueue_motion([(1, 3, 10.0, 1.0)], 0, &swing, |_| 1.0);
        for _ in 0..21 {
            m.tick(1.0);
        }
        assert!(m.done && m.finished(1));
        let mask = m.enqueue_motion([(2, 4, 10.0, 1.0)], 0, &Enq::status(1.0, 4.0, false), |_| 1.0);
        assert_eq!(mask, 1 << 2);
        assert!(m.finished(1), "region 1's finished swing stays");
        assert!(m.done, "no region 0 entry, so the flag stays up");
    }

    /// Row 4 (FUN_100ce160 -> FUN_1001b170(8.0)): the mouth region's entries go on for 8 ticks, then are dropped; a
    /// playing one keeps its weight, one still fading in keeps rising.
    #[test]
    fn mouth_fade_runs_8_ticks() {
        let mut m = q();
        let talk =
            Enq { share: 1.0, rate: 1.0, count: 1, blend: 8.0, out_len: 1.0, start: 0.0, end: 0.0, carry: false };
        m.enqueue(4, 1, 200.0, 1.0, &talk);
        for _ in 0..20 {
            m.tick(1.0);
        }
        m.enqueue(4, 2, 200.0, 1.0, &talk);
        m.tick(1.0);
        m.tick(1.0);
        m.fade_region(4, 8.0);
        assert_eq!(m.regions[4].iter().map(|e| e.state).collect::<Vec<_>>(), [FADE_OUT, FADE_BOTH]);
        for _ in 0..5 {
            m.tick(1.0);
        }
        // The newer one still rises on its slope under the older one.
        assert_eq!(m.regions[4].len(), 2);
        assert!((m.regions[4][1].weight - 7.0 / 8.0).abs() < 1e-4);
        m.tick(1.0);
        // The older one's 8 ticks (from the newer one's enqueue) are up.
        assert_eq!(m.regions[4].len(), 1);
        let f = m.regions[4][0].frame;
        m.tick(1.0);
        assert!(m.regions[4][0].frame > f, "the motion goes on while it fades");
        m.tick(1.0);
        assert!(m.regions[4].is_empty());
        assert!(!m.done, "regions 3 and up never raise the flag");
    }

    /// A counted motion of regions 3 and up (a blink, a `mou6` talk in region 6) ends by its weight running down
    /// over its out length; an overlay region's weight is its entries' shares folded by their weights.
    #[test]
    fn overlay_weight_and_counted_fade() {
        let mut m = q();
        let e = Enq { share: 0.5, rate: 1.0, count: 1, blend: 2.0, out_len: 8.0, start: 0.0, end: 0.0, carry: false };
        m.enqueue(6, 1, 4.0, 1.0, &e);
        // The first entry of the list is forced to weight 1 by the enqueue itself.
        let mut l = Vec::new();
        assert_eq!(m.layers(&mut l), [0.0, 0.5]);
        assert_eq!((l[0].weight, l[0].over, l[0].start), (1.0, 2, true));
        for _ in 0..8 {
            m.tick(1.0);
        }
        // 4 frames at half a frame a tick: over on the 8th tick, then 8 ticks down.
        assert_eq!(m.regions[6][0].state, FADE_BOTH);
        for _ in 0..4 {
            m.tick(1.0);
        }
        assert!((m.layers(&mut l)[1] - 0.25).abs() < 1e-4);
        for _ in 0..4 {
            m.tick(1.0);
        }
        assert!(m.regions[6].is_empty());
    }

    /// An entry under one at full weight is not posed; one at no weight neither.
    #[test]
    fn covered_entries_are_left_out() {
        let mut m = q();
        m.enqueue(0, 1, 40.0, 1.0, &Enq::status(1.0, 16.0, true));
        m.enqueue(0, 2, 40.0, 1.0, &Enq::status(1.0, 16.0, true));
        m.enqueue(3, 9, 6.0, 1.0, &Enq::status(1.0, 1.0, false));
        let mut l = Vec::new();
        m.layers(&mut l);
        // Region 3 first (higher regions win), then region 0: the new entry at weight 0 is not posed yet.
        assert_eq!(l.iter().map(|x| (x.region, x.anim)).collect::<Vec<_>>(), [(3, 9), (0, 1)]);
        m.regions[0][1].weight = 1.0;
        m.layers(&mut l);
        assert_eq!(l.iter().map(|x| (x.region, x.anim, x.start)).collect::<Vec<_>>(), [(3, 9, true), (0, 2, true)]);
    }

    /// A two-frame chunk at speed 1 (a bee's wings) steps a whole frame every 2 ticks, whatever the frame rate.
    #[test]
    fn two_frame_chunk_steps_every_two_ticks() {
        let e = Enq { share: 1.0, rate: 1.0, count: 0, blend: 1.0, out_len: 1.0, start: 0.0, end: 0.0, carry: false };
        let frames = |dt: f32, calls: usize| {
            let mut m = q();
            m.enqueue(1, 1, 2.0, 1.0, &e);
            (0..calls)
                .map(|_| {
                    m.tick(dt);
                    m.regions[1][0].frame
                })
                .collect::<Vec<_>>()
        };
        // 30 fps (2 ticks a frame): a step every call, as retail.
        assert_eq!(frames(2.0, 4), vec![1.0, 0.0, 1.0, 0.0]);
        // 144 fps: a step every 4.8 calls, not every call.
        let f = frames(60.0 / 144.0, 10);
        assert_eq!(f.iter().filter(|&&x| x == 1.0).count(), 5, "{f:?}");
        assert_eq!(f[3], 0.0);
        assert_eq!(f[4], 1.0);
    }

    /// FUN_1001a8e0: loops wrap, an end frame cuts the cycle short, a reverse rate wraps upward.
    #[test]
    fn frames_wrap() {
        let mut m = q();
        m.enqueue(0, 1, 10.0, 2.0, &Enq::status(1.0, 16.0, true));
        for _ in 0..12 {
            m.tick(1.0);
        }
        assert!((m.regions[0][0].frame - 2.0).abs() < 1e-4);
        m.regions[0][0].end = 4.0;
        m.tick(1.0);
        m.tick(1.0);
        assert!((m.regions[0][0].frame - 0.0).abs() < 1e-4);
        m.regions[0][0].rate = -1.0;
        m.tick(1.0);
        assert!((m.regions[0][0].frame - 3.0).abs() < 1e-4);
        m.set_rate(0.5);
        assert_eq!(m.regions[0][0].rate, 0.5);
    }
}
