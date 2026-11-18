//! The forced follow: s2c 0x037 u16 @0x46 names an actor index (our entity +0x2a2, cleared at entity init; LSB's
//! `warp_target_index`, which it never sets). While it names a live entity (FUN_10097a40), the head of our move step
//! FUN_100a6240 replaces the input: each retail frame we go a quarter of the way to that entity (all three axes),
//! or nowhere once its centre is inside our own radius (FUN_100aaef0), and the function returns before the bump test
//! and every turn. In third person we face the step; in first person (DAT_10489130) our yaw goes a quarter of the way
//! to the entity's own. In first person that entity is not drawn (FUN_100cd040) and has no name plate
//! (FUN_100d0510). FUN_100a6240 runs only where our input would (FUN_100a5dc0 / FUN_100a5ec0), so an event, a
//! charm or a status that takes no input stops the pull too.

use glam::Vec3;

/// The part of the remaining way one retail frame covers (FUN_100272e0(.., 0.25)).
const SHARE: f32 = 0.25;

/// One retail frame's move from `from` toward the entity at `to`: a quarter of the offset, none while the horizontal
/// distance is under our radius.
pub fn step(from: Vec3, to: Vec3, radius: f32) -> Vec3 {
    let d = to - from;
    if d.x.hypot(d.z) - radius < 0.0 { Vec3::ZERO } else { d * SHARE }
}

/// Third person: the entity yaw (+0xe8 = -atan2(z, x)) a step turns us to; none for a step with no x and no z.
pub fn face(step: Vec3) -> Option<f32> {
    (step.x != 0.0 || step.z != 0.0).then(|| -step.z.atan2(step.x))
}

/// First person: our entity yaw after one retail frame, a quarter of the way to the entity's (0x100a63xx: the
/// difference and the sum are each wrapped into -pi..pi with the constants 0x1032ad28 / 2c / 30).
pub fn ease(yaw: f32, to: f32) -> f32 {
    use std::f32::consts::{PI, TAU};
    let wrap = |a: f32| {
        let a = if a > PI { a - TAU } else { a };
        if a < -PI { a + TAU } else { a }
    };
    wrap(wrap(to - yaw) * SHARE + yaw)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// FUN_100a6240's head: a quarter of the way on every axis; inside our radius (horizontal) nothing.
    #[test]
    fn quarter_steps() {
        let s = step(Vec3::ZERO, Vec3::new(4.0, -2.0, 0.0), 0.32);
        assert_eq!(s, Vec3::new(1.0, -0.5, 0.0));
        assert_eq!(step(Vec3::ZERO, Vec3::new(0.2, -2.0, 0.2), 0.32), Vec3::ZERO);
        // The height does not count toward the touch test.
        assert_ne!(step(Vec3::ZERO, Vec3::new(0.4, 0.0, 0.0), 0.32), Vec3::ZERO);
    }

    /// Yaw 0 looks along +x and grows toward +z's far side (-atan2(z, x)); the first-person ease wraps.
    #[test]
    fn facing() {
        assert_eq!(face(Vec3::ZERO), None);
        assert_eq!(face(Vec3::new(0.0, 1.0, 0.0)), None);
        assert_eq!(face(Vec3::X), Some(0.0));
        assert!((face(Vec3::Z).unwrap() + std::f32::consts::FRAC_PI_2).abs() < 1e-6);
        assert!((ease(0.0, 1.0) - 0.25).abs() < 1e-6);
        // From 3.0 to -3.0 is the short way round, through pi.
        let e = ease(3.0, -3.0);
        assert!((e - (3.0 + (std::f32::consts::TAU - 6.0) * 0.25)).abs() < 1e-5, "{e}");
    }
}
