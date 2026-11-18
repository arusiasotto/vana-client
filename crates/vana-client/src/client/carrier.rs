//! Carrier statuses (FUN_1008cd90; docs/modlog/2026-11-10-carrier-statuses-136.md): a door whose state in force is
//! 0x1a / 0x1b (set 0) or 0x1d / 0x1e (set 1) publishes how far its first part moved since it last did, and every
//! unbound actor in status 0x1c (set 0) or 0x1f (set 1) moves by that each frame. No event script sets these
//! statuses (census dat::event::status_census); only the server's status byte can.

use super::World;
use glam::Vec3;

/// One set's globals (DAT_10486bb8.. / DAT_10486b98..): the part's place at the last publish and the step from
/// it. Retail never resets them, so a rider keeps the last step for as long as no carrier publishes.
#[derive(Clone, Copy, Default)]
struct Set {
    prev: Vec3,
    delta: Vec3,
}

#[derive(Default)]
pub struct Carriers {
    sets: [Set; 2],
    /// This frame's publishes by the carrier's index, in the actor table's order (FUN_10096640 updates index 0 up),
    /// and the step left by the frame before: an actor with a lower index than its carrier still sees the old one.
    pubs: [Vec<(u16, Vec3)>; 2],
    before: [Vec3; 2],
}

/// Set A (DAT_10485a08): the carrier statuses that publish its step, and the rider status that follows it.
const CARRIER_A: [u8; 2] = [0x1a, 0x1b];
const RIDER_A: u8 = 0x1c;
/// Set B (DAT_104859e8).
const CARRIER_B: [u8; 2] = [0x1d, 0x1e];
const RIDER_B: u8 = 0x1f;

/// The set a carrier status feeds.
pub fn carrier_set(status: u8) -> Option<usize> {
    if CARRIER_A.contains(&status) {
        Some(0)
    } else if CARRIER_B.contains(&status) {
        Some(1)
    } else {
        None
    }
}

/// The set a rider status follows.
pub fn rider_set(status: u8) -> Option<usize> {
    match status {
        RIDER_A => Some(0),
        RIDER_B => Some(1),
        _ => None,
    }
}

/// Entity +0x120 bit 21 as FUN_1008cd90 leaves it each frame: set for a carrier status (bound or not) and for an
/// unbound rider. With it the model takes no ground tilt and c2s 0x015 carries GroundMode (FUN_10084640's bits).
pub fn no_ground(status: u8, bound: bool) -> bool {
    carrier_set(status).is_some() || (!bound && rider_set(status).is_some())
}

impl Carriers {
    /// A frame starts: last frame's steps are what actors before any carrier get.
    pub fn begin(&mut self) {
        for k in 0..2 {
            self.before[k] = self.sets[k].delta;
            self.pubs[k].clear();
        }
    }

    /// A carrier's update: step = place - the last published place (whichever carrier published it).
    pub fn publish(&mut self, set: usize, index: u16, at: Vec3) {
        let s = &mut self.sets[set];
        s.delta = at - s.prev;
        s.prev = at;
        self.pubs[set].push((index, s.delta));
    }

    /// The step the actor at `index` adds this frame: the last one published before its turn.
    pub fn step(&self, set: usize, index: u16) -> Vec3 {
        self.pubs[set].iter().rev().find(|(i, _)| *i < index).map_or(self.before[set], |(_, d)| *d)
    }
}

/// The frame's publishes: door entities whose state in force is a carrier status, by index. The place is the first
/// part's translation (drawobj +0x624, scheduler op 0x0c's value); a door without a group has none and gives zero.
/// *(Retail reads an unset stack vector for a carrier that is not a door actor; ours publishes nothing for those.)*
pub fn update(w: &mut World) {
    w.carriers.begin();
    let mut doors: Vec<(u16, usize, u32)> = w
        .entities
        .iter()
        .filter(|(_, e)| e.door != 0)
        .filter_map(|(id, e)| Some((e.index, carrier_set(*w.doors.state.get(id)?)?, e.door)))
        .collect();
    doors.sort_unstable();
    for (index, set, door) in doors {
        let at = w
            .renderer
            .as_ref()
            .and_then(|r| r.part_pos(*r.door_parts.get(&door)?.first()?))
            .map_or(Vec3::ZERO, Vec3::from_array);
        w.carriers.publish(set, index, at);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rider_takes_the_carriers_step() {
        let mut c = Carriers::default();
        // The globals start at zero, so the first publish steps by the part's whole offset.
        c.begin();
        c.publish(0, 0x20, Vec3::new(0.0, -1.0, 0.0));
        assert_eq!(c.step(0, 0x400), Vec3::new(0.0, -1.0, 0.0));
        // An actor before the carrier in the table still has last frame's step (none yet).
        assert_eq!(c.step(0, 0x10), Vec3::ZERO);
        assert_eq!(c.step(1, 0x400), Vec3::ZERO);
        c.begin();
        c.publish(0, 0x20, Vec3::new(0.0, -1.5, 0.0));
        assert_eq!(c.step(0, 0x400), Vec3::new(0.0, -0.5, 0.0));
        assert_eq!(c.step(0, 0x10), Vec3::new(0.0, -1.0, 0.0));
        // No carrier this frame: the last step goes on (the globals are never cleared).
        c.begin();
        assert_eq!(c.step(0, 0x400), Vec3::new(0.0, -0.5, 0.0));
        // Two carriers on one set share the globals: the second steps from the first's place.
        c.begin();
        c.publish(1, 5, Vec3::X);
        c.publish(1, 9, Vec3::new(3.0, 0.0, 0.0));
        assert_eq!(c.step(1, 7), Vec3::X);
        assert_eq!(c.step(1, 0x400), Vec3::new(2.0, 0.0, 0.0));
    }

    #[test]
    fn statuses() {
        assert_eq!(
            [0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f].map(carrier_set),
            [Some(0), Some(0), None, Some(1), Some(1), None]
        );
        assert_eq!([0x1c, 0x1f, 0x1a, 0].map(rider_set), [Some(0), Some(1), None, None]);
        assert!(no_ground(0x1a, true) && no_ground(0x1e, false));
        assert!(no_ground(0x1c, false) && !no_ground(0x1c, true) && !no_ground(0, false));
    }
}
