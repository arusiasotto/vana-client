//! The lobby's "menu    netwait" (the status line) and "menu    netbar" (the progress) while an operation runs
//! (FUN_1023b550 / FUN_1023bb60). MODLOG "Lobby: netwait and netbar".
//!
//! The retail step machine runs one step-function call per lobby frame (30 fps); each call may set a group 8 status
//! text and moves the step's sub-step counter, and the bar is (finished steps' counts + sub) / the op's total. Ours
//! replays those calls from tables, never passing a wait for a view reply the worker has not read yet; the worker's
//! Task waits here until the bar has run, then p = 1 for 10 frames, then both windows close.
//!
//! The time-out (FUN_100edfe0 / FUN_100edff0, docs/modlog/2026-11-12-lobby-netwait-144.md): each step function zeroes
//! a call counter on its first call and counts the later ones; past 3599 the step fails with no link error, which the
//! popup shows as code 0x71, FFXI-3113. Step 1 counts only its reply waits from sub 14 and step 3 only below sub 10.

use super::Task;
use super::game_ui::GameUi;
use crate::net::lobby::Watch;
use std::sync::Arc;
use std::sync::atomic::Ordering;

/// The lobby operations (FUN_1023b550 param_4).
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Op {
    /// The lobby entry: connect, the lists.
    Connect,
    /// Log in with a character.
    Login,
    Delete,
    Create,
    NameCheck,
    Rename,
}

/// FUN_100edff0: the call that finds the counter past 0xe0f fails its step.
pub const TIMEOUT_CALLS: u32 = 0xe0f;
/// The popup's code for a step that failed with no link error (thunk_FUN_100efa60): FFXI-3113.
pub const TIMEOUT_CODE: u16 = 0x71;

/// How a run ends.
pub enum End {
    /// The windows closed; the worker's Task goes on.
    Task(Box<Task>),
    /// A step timed out; `refresh` in the list refresh after the change (steps 0x13 / 2: FFXI-3115 follows and the
    /// lobby is left, LAB_1023d0a6), else in step 1 or the op's own step (LAB_1023d116).
    TimedOut { op: Op, refresh: bool },
}

/// One step-function call: the status text it sets, the sub-step after it, and whether it waits for a view reply.
#[derive(Clone, Copy)]
struct Call {
    text: Option<u16>,
    sub: u32,
    reply: bool,
}

/// Whether a call of step `id` entered at sub-step `sub` counts towards the time-out (the first call of a step, sub 0,
/// zeroes the counter instead).
fn counted(id: u8, sub: u32) -> bool {
    match id {
        // FUN_100ed920: only its waits (cases 2, 6, 8, 10, 0xe, 0x10, 0x12, 0x14) once the sub-step is 0xe or more.
        1 => matches!(sub, 0xe | 0x10 | 0x12 | 0x14),
        // FUN_100ee2a0: while 0 < sub < 10.
        3 => (1..10).contains(&sub),
        // FUN_100ee0f0, FUN_100ee7d0 / 100eea40 / 100eecb0, FUN_100ef160, FUN_100ef220: every call after the first.
        _ => sub != 0,
    }
}

const fn c(text: Option<u16>, sub: u32, reply: bool) -> Call {
    Call { text, sub, reply }
}

/// FUN_100dbac0: a step's sub-step count, and its calls (FUN_100ed7e0, FUN_100edfb0, FUN_100ee160, FUN_100ee690 /
/// FUN_100ee900 / FUN_100eeb70, FUN_100ef020, FUN_100ee0a0). Step 1 on a live link jumps from sub 5 to 21; step 3
/// goes 14 -> 15 -> 22 for a linked character, through subs 16..21 for one it `registers` (docs/modlog rows 145, 146).
fn step(id: u8, fresh: bool, registers: bool) -> (u32, Vec<Call>) {
    match id {
        1 if fresh => {
            let text = |s: u32| match s {
                0 => Some(0),
                3 => Some(1),
                7 => Some(2),
                9 => Some(3),
                11 => Some(4),
                13 => Some(5),
                15 => Some(6),
                17 => Some(7),
                _ => None,
            };
            (21, (0..21).map(|s| c(text(s), s + 1, matches!(s, 14 | 16 | 18))).collect())
        }
        1 => (21, vec![c(Some(0), 3, false), c(Some(1), 4, false), c(None, 5, false), c(None, 21, false)]),
        2 => (4, vec![c(Some(8), 1, false), c(None, 2, true), c(None, 3, false), c(None, 4, false)]),
        3 if registers => {
            let (_, mut calls) = step(3, fresh, false);
            calls.truncate(calls.len() - 2);
            calls.extend([
                c(Some(0x10), 16, false),
                c(Some(0x12), 17, false),
                c(Some(0x13), 18, false),
                c(Some(0x14), 19, false),
                c(Some(0x15), 20, false),
                c(Some(0x10), 21, false),
                c(Some(0x11), 22, false),
            ]);
            (22, calls)
        }
        3 => (
            22,
            vec![
                c(Some(0xc4), 1, false),
                c(None, 2, true),
                c(Some(0xc5), 4, false),
                c(None, 5, false),
                c(None, 6, false),
                c(None, 7, false),
                c(None, 8, false),
                c(None, 10, false),
                c(Some(0xc), 11, false),
                c(Some(0xd), 12, false),
                c(Some(0xe), 13, false),
                c(Some(0xf), 14, false),
                c(Some(0x10), 15, false),
                c(Some(0x11), 22, false),
            ],
        ),
        4 | 0x14 | 0x16 => {
            let t = match id {
                4 => 0x16,
                0x14 => 0x17,
                _ => 0x18,
            };
            (
                10,
                vec![
                    c(Some(t), 1, false),
                    c(None, 2, false),
                    c(None, 3, false),
                    c(None, 4, true),
                    c(None, 5, false),
                    c(None, 10, false),
                ],
            )
        }
        5 => (2, vec![c(Some(0x1c), 1, false), c(None, 2, true)]),
        0x13 => (4, vec![c(Some(9), 1, false), c(None, 2, false), c(None, 3, false), c(None, 4, false)]),
        _ => (1, Vec::new()),
    }
}

/// A frame of the run: the text and bar after it, a reply wait, and the refusal point of steps 4 / 0x14 / 0x16.
#[derive(Clone, Copy)]
struct Frame {
    text: Option<u16>,
    p: Option<f32>,
    reply: bool,
    refusable: bool,
    /// The step's first call: the time-out counter starts over (FUN_100edfe0).
    first: bool,
    /// The call counts towards the time-out (FUN_100edff0).
    counted: bool,
    /// In the refresh after the op's own step.
    refresh: bool,
}

pub struct NetWait {
    pub op: Op,
    frames: Vec<Frame>,
    at: usize,
    text: Option<u16>,
    p: f32,
    replies: Arc<Watch>,
    base: u32,
    /// DAT_104cb7f8, the step's counted calls.
    calls: u32,
    /// Frames before the run starts: the caller's fade (FUN_1023fb20: 8, FUN_1023fc20: 24).
    lead: u32,
    passed: u32,
    parked: Option<(Task, bool)>,
    /// Frames left: of the p = 1 hold, or of a refusal's subs 6..9.
    hold: Option<u32>,
    acc: f32,
}

impl NetWait {
    /// FUN_1023b550: the op's steps (every caller passes param_3 = 0); `replies` is the link's reply counter.
    pub fn new(op: Op, replies: Arc<Watch>) -> Self {
        Self::build(op, replies, false)
    }

    /// The log-in's run; `registers` when the character is first registered to a PlayOnline handle
    /// (`Lobby::registers`).
    pub fn login(replies: Arc<Watch>, registers: bool) -> Self {
        Self::build(Op::Login, replies, registers)
    }

    fn build(op: Op, replies: Arc<Watch>, registers: bool) -> Self {
        let steps: &[u8] = match op {
            Op::Connect => &[1],
            Op::Login => &[1, 3],
            Op::Delete => &[1, 5, 0x13, 2],
            Op::Create => &[1, 4, 0x13, 2],
            Op::NameCheck => &[1, 0x14],
            Op::Rename => &[1, 0x16, 0x13, 2],
        };
        let built: Vec<(u32, Vec<Call>)> = steps.iter().map(|&s| step(s, op == Op::Connect, registers)).collect();
        let total = built.iter().map(|b| b.0).sum::<u32>().max(1) as f32;
        let mut frames = Vec::new();
        let mut done = 0;
        for (k, (n, calls)) in built.into_iter().enumerate() {
            // Each step start: two pump frames with the old text and bar.
            let pump = Frame {
                text: None,
                p: None,
                reply: false,
                refusable: false,
                first: false,
                counted: false,
                refresh: false,
            };
            frames.extend([pump; 2]);
            let refusable = matches!(steps[k], 4 | 0x14 | 0x16);
            // The refresh: steps 0x13 / 2 after the op's own step.
            let refresh = k >= 2;
            let mut sub = 0;
            for call in calls {
                frames.push(Frame {
                    text: call.text,
                    p: Some((done + call.sub) as f32 / total),
                    reply: call.reply,
                    refusable: refusable && call.reply,
                    first: sub == 0,
                    counted: counted(steps[k], sub),
                    refresh,
                });
                sub = call.sub;
            }
            // The call that returns done (sub = N).
            frames.push(Frame {
                text: None,
                p: Some((done + n) as f32 / total),
                counted: counted(steps[k], sub),
                refresh,
                ..pump
            });
            done += n;
        }
        replies.start();
        let base = replies.replies.load(Ordering::Relaxed);
        Self {
            op,
            frames,
            at: 0,
            text: None,
            p: 0.0,
            replies,
            base,
            calls: 0,
            lead: 0,
            passed: 0,
            parked: None,
            hold: None,
            acc: 0.0,
        }
    }

    /// The run starts `frames` later: the caller's fade-in plays first.
    pub fn after(mut self, frames: u32) -> Self {
        self.lead = frames;
        self
    }

    /// Whether the windows are up yet (not during the caller's fade).
    pub fn shown(&self) -> bool {
        self.lead == 0
    }

    /// The worker's Task waits here; `refused` for a lobby refusal (the step's subs 6..9, then no hold).
    pub fn park(&mut self, task: Task, refused: bool) {
        self.parked = Some((task, refused));
    }

    /// Per frame: the calls at 30 a second; Some once the windows close.
    pub fn update(&mut self, dt: f32) -> Option<End> {
        // A broken link closes both windows at once.
        if matches!(&self.parked, Some((t, _)) if super::task_failed(t)) {
            return self.parked.take().map(|p| End::Task(Box::new(p.0)));
        }
        self.acc += dt.min(0.5);
        while self.acc >= 1.0 / 30.0 {
            self.acc -= 1.0 / 30.0;
            if let Some(t) = self.tick() {
                return Some(t);
            }
        }
        None
    }

    fn tick(&mut self) -> Option<End> {
        if self.lead > 0 {
            self.lead -= 1;
            return None;
        }
        if let Some(n) = self.hold {
            if n == 0 {
                return self.parked.take().map(|p| End::Task(Box::new(p.0)));
            }
            self.hold = Some(n - 1);
            return None;
        }
        let Some(&f) = self.frames.get(self.at) else {
            // The table is done: p = 1 for 10 frames once the Task is in.
            if self.parked.is_some() {
                self.p = 1.0;
                self.hold = Some(10);
            }
            return None;
        };
        // This call of the step function: a step's first call zeroes the counter (no first call waits); a counted
        // one past the limit fails the step (step 1 polls its reply first and fails the same way).
        if f.first {
            self.calls = 0;
        } else if f.counted {
            self.calls += 1;
            // The worker stops waiting and hands the link back, its request still open (retail's link stays up). A
            // result already in wins: the step polls its reply first.
            if self.calls > TIMEOUT_CALLS && self.replies.give_up() {
                return Some(End::TimedOut { op: self.op, refresh: f.refresh });
            }
        }
        // A refusal point waits for the Task itself, which follows its reply at once.
        if f.refusable && self.parked.is_none() {
            return None;
        }
        if f.reply {
            let read = self.replies.replies.load(Ordering::Relaxed).wrapping_sub(self.base);
            // The reply is not in yet (a finished Task with fewer replies than the table passes anyway).
            if read <= self.passed && self.parked.is_none() {
                return None;
            }
            self.passed += 1;
            if self.parked.as_ref().is_some_and(|p| p.1) {
                if !f.refusable {
                    // A refused step with no sub-steps after its reply (step 5, the delete): the step fails on that
                    // call and both windows close at once (LAB_1023d116).
                    return self.parked.take().map(|p| End::Task(Box::new(p.0)));
                }
                self.hold = Some(4);
                self.frames.truncate(self.at);
            }
        }
        if let Some(t) = f.text {
            self.text = Some(t);
        }
        if let Some(p) = f.p {
            self.p = p;
        }
        self.at += 1;
        None
    }
}

/// What the wait shows: its text and the bar's progress (the modern layer's panel).
pub fn view(gu: &GameUi, nw: &NetWait) -> (String, f32) {
    (nw.text.map_or(String::new(), |t| gu.lobby_msg(8, t as usize, "")), nw.p)
}

/// Both windows (FUN_102408a0 / FUN_102409a0), centred as the prompts: the status text in netwait's frame, then the
/// netbar track (lobbywin 81, frameless) with its fill, lobbywin 77 from the track's left edge, 256 p wide, while
/// 0.01 < p < 1.1.
pub fn draw(gu: &mut GameUi, nw: &NetWait, w: f32, h: f32) {
    let (text, _) = view(gu, nw);
    gu.netwait_window(&text, w, h);
    gu.netbar_window(nw.p, w, h);
}

#[cfg(test)]
mod tests {
    use super::*;

    fn run(nw: &mut NetWait, frames: u32) -> Option<End> {
        (0..frames).find_map(|_| nw.tick())
    }

    /// FUN_100edff0: a reply that never comes fails the step on the call that finds the counter past 0xe0f; the
    /// worker is told to stop waiting. Step 1's wait at sub 14 is the first counted call of the connect.
    #[test]
    fn a_missing_reply_times_out_after_3600_calls() {
        let watch: Arc<Watch> = Default::default();
        let mut nw = NetWait::new(Op::Connect, watch.clone());
        // Two pump frames and the calls of subs 0..13 pass; the wait's calls 1..=3599 do not fail.
        assert!(run(&mut nw, 2 + 14 + TIMEOUT_CALLS).is_none());
        assert!(!watch.given_up());
        assert!(matches!(nw.tick(), Some(End::TimedOut { op: Op::Connect, refresh: false })));
        assert!(watch.given_up() && !watch.finish());
    }

    /// A worker whose result is in when the count runs out wins the race: no time-out, its Task goes on.
    #[test]
    fn a_result_in_before_the_time_out_goes_on() {
        let watch: Arc<Watch> = Default::default();
        let mut nw = NetWait::new(Op::Connect, watch.clone());
        assert!(run(&mut nw, 2 + 14 + TIMEOUT_CALLS).is_none());
        assert!(watch.finish());
        assert!(nw.tick().is_none() && !watch.given_up());
        watch.replies.fetch_add(3, Ordering::Relaxed);
        nw.park(Task::LobbyBack(None), false);
        assert!(matches!(run(&mut nw, 100), Some(End::Task(t)) if matches!(*t, Task::LobbyBack(None))));
    }

    /// Step 3 for a character no PlayOnline handle holds yet (FUN_100ee2a0 subs 0xe, 0x10..0x15): the same calls up
    /// to sub 14, then the link's texts 8 0x12..0x15 and subs 14 / 15 again.
    #[test]
    fn step_3_registering_a_character() {
        let (n, plain) = step(3, false, false);
        let (m, reg) = step(3, false, true);
        assert_eq!((n, m), (22, 22));
        assert_eq!(reg.len(), plain.len() + 5);
        let tail: Vec<(Option<u16>, u32)> = reg[plain.len() - 2..].iter().map(|c| (c.text, c.sub)).collect();
        assert_eq!(
            tail,
            [
                (Some(0x10), 16),
                (Some(0x12), 17),
                (Some(0x13), 18),
                (Some(0x14), 19),
                (Some(0x15), 20),
                (Some(0x10), 21),
                (Some(0x11), 22)
            ]
        );
        assert!(
            reg.iter()
                .zip(&plain)
                .take(plain.len() - 2)
                .all(|(a, b)| (a.text, a.sub, a.reply) == (b.text, b.sub, b.reply))
        );
    }

    /// The counter starts over with each step, and a time-out in the refresh after a change is told apart (FFXI-3115
    /// follows it).
    #[test]
    fn the_refresh_times_out_on_its_own_count() {
        let watch: Arc<Watch> = Default::default();
        let mut nw = NetWait::new(Op::Delete, watch.clone());
        // Step 1 on a live link (2 + 5 frames), step 5 up to its wait (2 + 1), then 3000 calls of waiting.
        assert!(run(&mut nw, 7 + 3 + 3000).is_none());
        // The 0x03 comes: step 5 ends, step 0x13 runs (no link), step 2 asks for the list and waits.
        watch.replies.fetch_add(1, Ordering::Relaxed);
        assert!(run(&mut nw, 2 + (2 + 5) + (2 + 1) + TIMEOUT_CALLS).is_none());
        assert!(matches!(nw.tick(), Some(End::TimedOut { op: Op::Delete, refresh: true })));
    }

    /// Step 3 counts only below sub 10 (FUN_100ee2a0), step 1 only its waits from sub 14 (FUN_100ed920).
    #[test]
    fn counted_calls() {
        assert!(!counted(1, 0xd) && counted(1, 0xe) && !counted(1, 0xf) && counted(1, 0x14) && !counted(1, 10));
        assert!(!counted(3, 0) && counted(3, 1) && counted(3, 9) && !counted(3, 10));
        assert!(!counted(2, 0) && counted(2, 1) && counted(0x13, 3) && counted(5, 1) && counted(0x16, 9));
    }

    /// The caller's fade plays before the run (FUN_1023fb20's 8 frames).
    #[test]
    fn the_run_starts_after_the_fade() {
        let mut nw = NetWait::new(Op::Login, Default::default()).after(8);
        assert!(!nw.shown());
        assert!(run(&mut nw, 8).is_none());
        assert!(nw.shown() && nw.at == 0);
    }
}
