<!-- dll-build: 30261102_0 -->
## Gamepad: retail's controller choice (padguid000) and DirectInput read on Windows (2026-11-19)

- Setup (FUN_100058f0 -> FUN_100083d0): DirectInput8Create into pad +0x84. With padmode000's [5] (XInput,
  DAT_10456de8) FUN_10008d90 checks the game folder's xinputdll.dll loads (+0xc9a) and returns when it does not (no
  controller at all); FUN_10008e10 takes XInputGetState_ / SetState_ / Enable_. Then EnumDevices(GAMECTRL, FUN_100057d0)
  with DIEDFL_ATTACHEDONLY | DIEDFL_FORCEFEEDBACK when padmode000's [1] is on, and again with ATTACHEDONLY alone when
  that failed or created no device. The constant force effect is made only for a device the first pass created.
- padmode000's flags (FUN_10005490): [0] DAT_10456de4 on, [1] de9 force feedback, [2] de6 sliders, [3] de5 hat,
  [4] de7 background, [5] de8 XInput. FFXiPadConfig's own defaults are 0,1,1,1,0,0 (its +0x820 .. +0x834).
- FUN_100057d0, per device: with no padguid000 (DAT_10456cc0 nil) +0xc9c = 0; an XInput device (with +0xc9a)
  sets +0xc99 and the enumeration goes on, so a later DirectInput device is created too and is the one read; any other
  is created (+0x90) and stops it (a failed CreateDevice goes on). With padguid000, every XInput device counts
  +0xc9c up (from -1, FUN_10005660 / DAT_10456df0) and the one named stops it: XInput (+0xc99) or created.
- FUN_10008ab0, the XInput test: WMI Win32_PNPEntity DeviceIDs; one with "IG_" whose VID_ / PID_ (swscanf %4X) make
  the device's guidProduct.Data1 (PID << 16 | VID). Returns 1 on a match.
- Device setup: DIDEVCAPS polled flags (2 | 8) -> +0xc98 (Poll each frame); DIPROP_BUFFERSIZE 0x140; c_dfDIJoystick2
  (0x1034b23c, the library's 164 objects); DISCL_EXCLUSIVE | FOREGROUND, or BACKGROUND with [4]; DIPROP_RANGE ±127
  by offset on 0x00 .. 0x1c; Acquire; with force feedback EnumObjects(DIDFT_AXIS) counts the FF actuators
  (FUN_100083b0, at most 2) and CreateEffect(GUID_ConstantForce, cartesian, object offsets, infinite, gain 10000,
  axes lX / lY, magnitude 0) into DAT_10456dd8.
- FUN_10005a40: a settings change (DAT_10456df0: padguid000, or [0] / [1] / [5] changed) lets the device go, sets
  +0xc9c -1 / +0xc99 0 and runs FUN_100083d0 again. No device: +0xc99 reads XInput slot +0xc9c; else, with the pad on,
  FUN_100083d0 runs again every 0x5b-th frame (+0xda4; +0xc9c not reset). A device: Poll (+0xc98), the rumble
  (FUN_10007ae0), GetDeviceState(0x110); 0x8007001E / 0x8007000C / 0x800700AA let it go, other failures read nothing.
- The DirectInput branch: buttons 0 .. 31 (rgbButtons' high bit) through padsin; axis codes (jump table 0x10007788,
  negative inverted) 1 .. 6 lX lY lZ lRx lRy lRz, 7 / 8 the sliders with [2], 9 / 10 the first hat's X / Y with [3]
  (FUN_100059c0 / FUN_10005a00, ±127 outside 22.5-degree bands). Slot 25 keeps the d-pad bits (the XInput branch
  drops them). After the per-axis 42 dead zone the movement stick past x² + y² > 0x25cd is scaled by
  (x² + y²) / max(x², y²) (ftol), then held to ±127.
- FUN_10007ae0's DirectInput branch: the same level and 5-tick hold as XInput's; m = level x 10000 >> 8; one force
  axis: direction 0, magnitude m; two: direction (m, m), magnitude ftol(sqrt(2 m²)); nothing when it and the last
  are 0; SetParameters(DIEP_START | TYPESPECIFICPARAMS | DIRECTION). WM_ACTIVATE (FUN_100087d0) acquires the device.
- FFXiPadConfig lists the attached game controllers (FUN_00404660) and writes the pick's guidInstance with
  StringFromGUID2 (FUN_0040e1e0); the game reads it with CLSIDFromString (FUN_10019060) when the pad is on.
- Ours: client/gamepad_dinput.rs, and gamepad.rs's Windows path (gilrs is not started once DirectInput is up); the
  Controller window lists DirectInput's controllers and saves config gamepad_padguid, and padmode000's [5] / [2] / [3]
  as gamepad_xinput / gamepad_sliders / gamepad_hat, each only when it is changed. Use XInput turned off waits for the
  next start, as +0xc9a stays set once the DLL loaded (the window says so). Not retail: SetupAPI's instance IDs for WMI's DeviceIDs (the
  same present devices); the IDirectInput8W interface; xinput1_3 (then 1_4 / 9_1_0) for xinputdll.dll; XInput slot
  0 when nothing is picked (an empty slot read once a second); no buffered GetDeviceData (a press and release inside one frame is lost); the round dead
  zone; a background option change also picks again; Linux and macOS list gilrs's pads and keep gilrs's UUID in
  padguid.
- Review round (2026-11-22): with nothing saved, a controller read through DirectInput plays FFXiPadConfig's Pattern A
  (menu 0x410, record 0x6ef598 that FUN_0040dfc0 applies: "console-type gamepads with 2 directional control devices
  and 16 buttons"), not the XInput layout, whose axis codes are XInput's. The tool's records are 34 dwords: padsin000
  is dwords 0..26 and 29..33, dword 27's bytes the force feedback / hat / sliders / background options, dword 28's
  byte XInput. Not retail: the game has no default per device. The rescan every 0x5b frames enumerates on a thread
  of its own (its own IDirectInput8) and the setup runs on the frame only when it found a controller the pick takes.
