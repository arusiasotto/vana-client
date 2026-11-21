//! Android's controllers as gamepad.rs's [`Pad`] (the virtual buttons and axes gilrs and SDL give).
//!
//! NativeActivity delivers pad events on the NDK input queue, which winit reads; the patched winit
//! (patches/winit/VANA.md) calls the `vana_android_gamepad_*` hooks below instead of making touches and keys of them.

use super::gamepad::Pad;
use std::sync::Mutex;

static PAD: Mutex<Pad> = Mutex::new(Pad { buttons: Vec::new(), axes: [0.0; 6] });
static SEEN: Mutex<bool> = Mutex::new(false);
/// The hat is what is holding the D-pad. Stick motion also reports hat 0,0, which must not release a D-pad that
/// arrived as a key.
static HAT_OWNS: Mutex<bool> = Mutex::new(false);

/// A trigger past this (0 ..= 1) also holds the L2 / R2 virtual button, as gilrs and SDL.
const TRIGGER_PRESS: f32 = 0.75;

pub fn state() -> Option<Pad> {
    let p = PAD.lock().unwrap().clone();
    if !*SEEN.lock().unwrap() && p.buttons.is_empty() && p.axes.iter().all(|a| *a == 0.0) {
        return None;
    }
    Some(p)
}

pub fn name() -> Option<String> {
    state().map(|_| "Android controller".into())
}

/// Axes as XInput / gilrs: left X/Y, right X/Y, LT, RT; Y up positive.
fn set_axes(lx: f32, ly: f32, rx: f32, ry: f32, lt: f32, rt: f32) {
    let mut p = PAD.lock().unwrap();
    // Android joystick Y is up-negative; XInput / gilrs / retail want up positive.
    let lt = lt.clamp(0.0, 1.0);
    let rt = rt.clamp(0.0, 1.0);
    p.axes = [lx.clamp(-1.0, 1.0), (-ly).clamp(-1.0, 1.0), rx.clamp(-1.0, 1.0), (-ry).clamp(-1.0, 1.0), lt, rt];
    // Analog triggers also drive virtual L2 / R2 (9 / 12), as SDL's gamepad backend.
    set_button_locked(&mut p, 9, lt > TRIGGER_PRESS);
    set_button_locked(&mut p, 12, rt > TRIGGER_PRESS);
    *SEEN.lock().unwrap() = true;
}

fn set_button_locked(p: &mut Pad, virtual_btn: u8, down: bool) {
    if down {
        if !p.buttons.contains(&virtual_btn) {
            p.buttons.push(virtual_btn);
            p.buttons.sort_unstable();
        }
    } else {
        p.buttons.retain(|b| *b != virtual_btn);
    }
}

fn set_button(virtual_btn: u8, down: bool) {
    let mut p = PAD.lock().unwrap();
    set_button_locked(&mut p, virtual_btn, down);
    *SEEN.lock().unwrap() = true;
}

/// Android `KeyEvent` keycodes to padsin's virtual numbers (XInput's layout, as SDL and gilrs).
fn map_keycode(code: i32) -> Option<u8> {
    Some(match code {
        97 => 0,   // BUTTON_B (East)
        99 => 1,   // BUTTON_X (West)
        100 => 2,  // BUTTON_Y (North)
        96 => 3,   // BUTTON_A (South / confirm)
        22 => 4,   // DPAD_RIGHT
        21 => 5,   // DPAD_LEFT
        19 => 6,   // DPAD_UP
        20 => 7,   // DPAD_DOWN
        102 => 8,  // BUTTON_L1
        104 => 9,  // BUTTON_L2
        106 => 10, // BUTTON_THUMBL
        103 => 11, // BUTTON_R1
        105 => 12, // BUTTON_R2
        107 => 13, // BUTTON_THUMBR
        108 => 14, // BUTTON_START
        109 => 15, // BUTTON_SELECT
        _ => return None,
    })
}

/// Virtual D-pad buttons (right, left, up, down) from one hat sample. `owns` stays set while a non-centered hat is
/// what holds them, so a later 0,0 is that press releasing. A stick sample is also 0,0 and must leave a key-held
/// D-pad alone.
fn hat_buttons(buttons: &mut Vec<u8>, owns: &mut bool, hat_x: f32, hat_y: f32) {
    let live = hat_x.abs() >= 0.5 || hat_y.abs() >= 0.5;
    if !live {
        if *owns {
            buttons.retain(|b| !matches!(*b, 4 | 5 | 6 | 7));
            *owns = false;
        }
        return;
    }
    *owns = true;
    let want = [(4, hat_x > 0.5), (5, hat_x < -0.5), (6, hat_y < -0.5), (7, hat_y > 0.5)];
    for (b, down) in want {
        if down {
            if !buttons.contains(&b) {
                buttons.push(b);
            }
        } else {
            buttons.retain(|x| *x != b);
        }
    }
    buttons.sort_unstable();
}

fn apply_hat(hat_x: f32, hat_y: f32) {
    let mut p = PAD.lock().unwrap();
    let mut owns = HAT_OWNS.lock().unwrap();
    hat_buttons(&mut p.buttons, &mut owns, hat_x, hat_y);
    drop(owns);
    drop(p);
    *SEEN.lock().unwrap() = true;
}

/// Called from the patched winit android input path (AInputQueue joystick / gamepad motion).
#[unsafe(no_mangle)]
pub extern "C" fn vana_android_gamepad_motion(
    lx: f32,
    ly: f32,
    rx: f32,
    ry: f32,
    lt: f32,
    rt: f32,
    hat_x: f32,
    hat_y: f32,
) {
    let _ = std::panic::catch_unwind(|| {
        set_axes(lx, ly, rx, ry, lt, rt);
        apply_hat(hat_x, hat_y);
    });
}

/// Called from the patched winit android input path (AInputQueue gamepad keys).
#[unsafe(no_mangle)]
pub extern "C" fn vana_android_gamepad_key(key_code: i32, down: bool) {
    let _ = std::panic::catch_unwind(|| {
        if let Some(b) = map_keycode(key_code) {
            set_button(b, down);
        }
    });
}

#[cfg(test)]
mod tests {
    use super::hat_buttons;

    #[test]
    fn hat_release_clears_the_dpad() {
        let mut buttons = Vec::new();
        let mut owns = false;
        hat_buttons(&mut buttons, &mut owns, 0.0, 1.0);
        assert_eq!(buttons, vec![7]);
        assert!(owns);
        // The release is hat 0,0. Leaving it held is the infinite scroll.
        hat_buttons(&mut buttons, &mut owns, 0.0, 0.0);
        assert!(buttons.is_empty());
        assert!(!owns);
    }

    #[test]
    fn stick_center_does_not_drop_a_key_dpad() {
        let mut buttons = vec![7];
        let mut owns = false;
        hat_buttons(&mut buttons, &mut owns, 0.0, 0.0);
        assert_eq!(buttons, vec![7]);
        assert!(!owns);
    }

    #[test]
    fn hat_changes_direction() {
        let mut buttons = Vec::new();
        let mut owns = false;
        hat_buttons(&mut buttons, &mut owns, 0.0, 1.0);
        hat_buttons(&mut buttons, &mut owns, 1.0, 0.0);
        assert_eq!(buttons, vec![4]);
        hat_buttons(&mut buttons, &mut owns, 0.0, 0.0);
        assert!(buttons.is_empty());
    }
}
