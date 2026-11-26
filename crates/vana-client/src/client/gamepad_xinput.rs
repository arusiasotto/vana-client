//! XInput as gamepad.rs's fallback on Windows, used while gilrs (Windows.Gaming.Input) has no pad. Some Wine front
//! ends on Android hook XInputGetState in the process but never make a WGI device, so gilrs sees nothing.
//! Retail's own XInput branch: FUN_10008e10 loads xinputdll.dll from the game folder (32-bit, a wrapper that links
//! XINPUT1_3.dll) and takes XInputGetState_ / XInputSetState_ / XInputEnable_; FUN_10005a40 reads its slot each frame
//! through FUN_10008ea0 and turns it into the pad word with table 0x1032a818. The slot (pad +0xc9c) comes from the
//! DirectInput enumeration FUN_100057d0 (gamepad_dinput.rs): with no padguid000 the first pad, slot 0; with
//! padguid000, the count of XInput pads (FUN_10008ab0) enumerated up to that one. Ours: xinput1_3 itself, and the
//! values raw as retail reads them (no dead zone or rescale here).

use super::gamepad::Pad;

/// XINPUT_GAMEPAD.
#[repr(C)]
#[derive(Clone, Copy, Default, PartialEq, Debug)]
pub struct XGamepad {
    pub buttons: u16,
    pub left_trigger: u8,
    pub right_trigger: u8,
    pub thumb_lx: i16,
    pub thumb_ly: i16,
    pub thumb_rx: i16,
    pub thumb_ry: i16,
}

/// Table 0x1032a818: wButtons' mask to padsin's virtual number. The triggers (0x10000 / 0x20000 there) are the bytes.
const VIRTUAL: [(u16, u8); 14] = [
    (0x0001, 6),  // d-pad up
    (0x0002, 7),  // d-pad down
    (0x0004, 5),  // d-pad left
    (0x0008, 4),  // d-pad right
    (0x1000, 3),  // A
    (0x2000, 0),  // B
    (0x4000, 1),  // X
    (0x8000, 2),  // Y
    (0x0010, 14), // Start
    (0x0020, 15), // Back
    (0x0040, 10), // left thumb
    (0x0080, 13), // right thumb
    (0x0100, 8),  // left shoulder
    (0x0200, 11), // right shoulder
];

/// One XInput state as gamepad.rs reads a pad. FUN_10005a40: a trigger is its button held at any value but 0, and a
/// thumb is v x 127 >> 15 (so axes x 127 gives retail's -127 ..= 126 exactly); XInput's up is already positive.
pub fn pad_of(g: &XGamepad) -> Pad {
    let mut buttons: Vec<u8> = VIRTUAL.iter().filter(|(m, _)| g.buttons & m != 0).map(|(_, n)| *n).collect();
    buttons.extend([(g.left_trigger, 9), (g.right_trigger, 12)].into_iter().filter(|(v, _)| *v != 0).map(|(_, n)| n));
    buttons.sort_unstable();
    let thumb = |v: i16| ((v as i32 * 127) >> 15) as f32 / 127.0;
    Pad {
        buttons,
        axes: [
            thumb(g.thumb_lx),
            thumb(g.thumb_ly),
            thumb(g.thumb_rx),
            thumb(g.thumb_ry),
            g.left_trigger as f32 / 255.0,
            g.right_trigger as f32 / 255.0,
        ],
        di: None,
    }
}

#[cfg(windows)]
pub use dll::XInput;

#[cfg(windows)]
mod dll {
    use super::{XGamepad, pad_of};
    use crate::client::gamepad::Pad;
    use windows_sys::Win32::Foundation::{FreeLibrary, HMODULE};
    use windows_sys::Win32::System::LibraryLoader::{
        GetProcAddress, LOAD_LIBRARY_SEARCH_APPLICATION_DIR, LOAD_LIBRARY_SEARCH_SYSTEM32, LoadLibraryExW,
    };

    /// XINPUT_STATE.
    #[repr(C)]
    #[derive(Default)]
    struct State {
        packet: u32,
        pad: XGamepad,
    }

    /// XINPUT_VIBRATION.
    #[repr(C)]
    struct Vibration {
        left: u16,
        right: u16,
    }

    type GetState = unsafe extern "system" fn(u32, *mut State) -> u32;
    type SetState = unsafe extern "system" fn(u32, *mut Vibration) -> u32;
    type Enable = unsafe extern "system" fn(i32);

    /// xinput1_3 as retail's xinputdll.dll links it. *(Not retail: xinput1_4 and xinput9_1_0 when it is missing; it
    /// comes with the DirectX redistributable, which a Windows without retail installed may lack.)*
    const DLLS: [&str; 3] = ["xinput1_3.dll", "xinput1_4.dll", "xinput9_1_0.dll"];
    /// How often an empty slot is read again, outside retail's pick.
    const EMPTY_POLL: std::time::Duration = std::time::Duration::from_secs(1);

    pub struct XInput {
        name: &'static str,
        module: HMODULE,
        /// The user index read (pad +0xc9c).
        slot: u32,
        get: GetState,
        set: Option<SetState>,
        enable: Option<Enable>,
        /// The slot's state this frame (None: no pad).
        state: Option<XGamepad>,
        /// The motors' level, and XInputEnable's last value.
        motor: u16,
        enabled: Option<bool>,
        /// An empty slot is read again from then on, not every frame (below).
        next_poll: Option<std::time::Instant>,
    }

    impl XInput {
        pub fn new() -> Result<XInput, String> {
            for name in DLLS {
                let wide: Vec<u16> = name.encode_utf16().chain([0]).collect();
                // The exe's folder (a front end's shim) and System32 only, never the working directory or PATH.
                let search = LOAD_LIBRARY_SEARCH_APPLICATION_DIR | LOAD_LIBRARY_SEARCH_SYSTEM32;
                let module = unsafe { LoadLibraryExW(wide.as_ptr(), std::ptr::null_mut(), search) };
                if module.is_null() {
                    continue;
                }
                let proc = |n: &std::ffi::CStr| unsafe { GetProcAddress(module, n.as_ptr().cast()) };
                let (get, set, enable) = (proc(c"XInputGetState"), proc(c"XInputSetState"), proc(c"XInputEnable"));
                let Some(get) = get else {
                    log::info!("gamepad (XInput): {name} has no XInputGetState");
                    unsafe { FreeLibrary(module) };
                    continue;
                };
                // SAFETY: these are the functions' signatures in every XInput DLL (XInputEnable is BOOL -> void).
                type Proc = unsafe extern "system" fn() -> isize;
                let (get, set, enable) = unsafe {
                    (
                        std::mem::transmute::<Proc, GetState>(get),
                        set.map(|f| std::mem::transmute::<Proc, SetState>(f)),
                        enable.map(|f| std::mem::transmute::<Proc, Enable>(f)),
                    )
                };
                log::info!("gamepad: XInput ({name})");
                return Ok(XInput {
                    name,
                    module,
                    slot: 0,
                    get,
                    set,
                    enable,
                    state: None,
                    motor: 0,
                    enabled: None,
                    next_poll: None,
                });
            }
            Err("no XInput DLL".into())
        }

        /// The user index to read (FUN_100057d0's +0xc9c); a new one starts with no pad and its motors off.
        pub fn set_slot(&mut self, slot: u32) {
            if slot != self.slot {
                self.motors(0);
                (self.slot, self.state, self.next_poll) = (slot, None, None);
            }
        }

        /// FUN_10005a40's poll (FUN_10008ea0): the slot's state, every frame when retail's pick found an XInput pad
        /// (`picked`) or a pad is there. *(Not retail: the slot-0 fallback with nothing picked reads an empty slot
        /// once a second, as Microsoft advises (a read of a disconnected slot is slow on some XInput versions);
        /// retail reads XInput only once its DirectInput pick found an XInput pad.)*
        pub fn update(&mut self, picked: bool) {
            let now = std::time::Instant::now();
            if self.next_poll.is_some_and(|t| now < t) {
                return;
            }
            let mut s = State::default();
            // ERROR_SUCCESS; anything else (ERROR_DEVICE_NOT_CONNECTED) is no pad.
            let pad = (unsafe { (self.get)(self.slot, &mut s) } == 0).then_some(s.pad);
            self.next_poll = (pad.is_none() && !picked).then(|| now + EMPTY_POLL);
            match (self.state.is_some(), pad.is_some()) {
                (false, true) => log::info!("gamepad (XInput) {} connected through {}", self.slot + 1, self.name),
                (true, false) => {
                    log::info!("gamepad (XInput) {} disconnected", self.slot + 1);
                    self.motor = 0;
                }
                _ => {}
            }
            self.state = pad;
        }

        /// The pad, as gamepad.rs reads one.
        pub fn state(&self) -> Option<Pad> {
            self.state.as_ref().map(pad_of)
        }

        /// The connected pad's name.
        pub fn names(&self) -> Vec<String> {
            self.state.iter().map(|_| format!("XInput controller {} ({})", self.slot + 1, self.name)).collect()
        }

        /// FUN_10005a40 calls FUN_10008f00 (XInputEnable) with the focus each frame, unless the background option
        /// is on and the game is in the background: the pad reads and rumbles only while `on`.
        pub fn enable(&mut self, on: bool) {
            if let Some(f) = self.enable.filter(|_| self.enabled != Some(on)) {
                unsafe { f(on as i32) };
                self.enabled = Some(on);
            }
        }

        /// Both motors at `level` (FUN_10008ed0, XInputSetState).
        pub fn motors(&mut self, level: u16) {
            if let Some(set) = self.set.filter(|_| level != self.motor) {
                unsafe { set(self.slot, &mut Vibration { left: level, right: level }) };
                self.motor = level;
            }
        }
    }

    impl Drop for XInput {
        fn drop(&mut self) {
            self.motors(0);
            unsafe { FreeLibrary(self.module) };
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn buttons_and_triggers_as_retail() {
        // A, B, Start, d-pad up; a trigger at 1 of 255 is held (FUN_10005a40 tests the byte against 0).
        let g = XGamepad { buttons: 0x1000 | 0x2000 | 0x0010 | 0x0001, left_trigger: 1, ..Default::default() };
        let p = pad_of(&g);
        assert_eq!(p.buttons, vec![0, 3, 6, 9, 14]);
        let g = XGamepad { buttons: 0x0300 | 0x00c0 | 0x0020 | 0xc000, right_trigger: 255, ..Default::default() };
        assert_eq!(pad_of(&g).buttons, vec![1, 2, 8, 10, 11, 12, 13, 15]);
    }

    #[test]
    fn thumbs_as_retail() {
        // v x 127 >> 15, arithmetic: full up 126, full down -127, -1 to -1.
        let g = XGamepad { thumb_lx: 32767, thumb_ly: -32768, thumb_rx: -1, thumb_ry: 259, ..Default::default() };
        let a = pad_of(&g).axes;
        let back: Vec<i32> = a[..4].iter().map(|v| (v * 127.0).round() as i32).collect();
        assert_eq!(back, vec![126, -127, -1, 1]);
        assert_eq!((a[4], a[5]), (0.0, 0.0));
    }
}
