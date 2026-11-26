//! Retail's controller choice and DirectInput read on Windows (FFXiMain's pad object, DAT_10456dd0). FUN_100058f0
//! makes the DirectInput8 interface (+0x84) and FUN_100083d0 picks the controller: with the XInput option
//! (padmode000's [5]) it first checks xinputdll.dll loads (FUN_10008d90, +0xc9a) and stops there when it does not;
//! then EnumDevices(DI8DEVCLASS_GAMECTRL) with FUN_100057d0 as the callback, attached force feedback devices first
//! when the rumble option is on (padmode000's [1]), else (or when that found no DirectInput device) every attached
//! one. The callback takes padguid000 (DAT_10456cc0): with none, the first device; with one, that device. An XInput
//! device (FUN_10008ab0) is read through XInput at the slot counted in +0xc9c (+0xc99 set); any other is created
//! (+0x90) and read with GetDeviceState in FUN_10005a40's DirectInput branch. A lost device is let go and the
//! enumeration runs again after 0x5a frames (+0xda4).

#![cfg_attr(not(windows), allow(dead_code))]

/// A GUID (the DirectInput instance GUID padguid000 names), laid out as Windows'.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Guid {
    pub data1: u32,
    pub data2: u16,
    pub data3: u16,
    pub data4: [u8; 8],
}

impl Guid {
    pub fn is_nil(&self) -> bool {
        *self == Guid::default()
    }

    /// CLSIDFromString as the game reads padguid000 (FUN_10019060): "{XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX}"; anything
    /// else is the nil GUID (the first controller).
    pub fn parse(s: &str) -> Guid {
        let s = s.trim();
        let Some(body) = s.strip_prefix('{').and_then(|s| s.strip_suffix('}')) else { return Guid::default() };
        let parts: Vec<&str> = body.split('-').collect();
        let lens = [8, 4, 4, 4, 12];
        if parts.len() != 5
            || parts.iter().zip(lens).any(|(p, n)| p.len() != n || !p.bytes().all(|b| b.is_ascii_hexdigit()))
        {
            return Guid::default();
        }
        let hex = |s: &str| u64::from_str_radix(s, 16).unwrap_or(0);
        let mut data4 = [0u8; 8];
        let tail = format!("{}{}", parts[3], parts[4]);
        for (i, b) in data4.iter_mut().enumerate() {
            *b = hex(&tail[i * 2..i * 2 + 2]) as u8;
        }
        Guid { data1: hex(parts[0]) as u32, data2: hex(parts[1]) as u16, data3: hex(parts[2]) as u16, data4 }
    }

    /// StringFromGUID2, as FFXiPadConfig writes padguid000 (FUN_0040e1e0).
    pub fn text(&self) -> String {
        let d = self.data4;
        format!(
            "{{{:08X}-{:04X}-{:04X}-{:02X}{:02X}-{:02X}{:02X}{:02X}{:02X}{:02X}{:02X}}}",
            self.data1, self.data2, self.data3, d[0], d[1], d[2], d[3], d[4], d[5], d[6], d[7]
        )
    }
}

/// DIJOYSTATE2, as c_dfDIJoystick2 (0x1034b23c) lays it out and GetDeviceState(0x110) fills it.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct JoyState {
    /// lX, lY, lZ, lRx, lRy, lRz.
    pub axes: [i32; 6],
    pub sliders: [i32; 2],
    pub pov: [u32; 4],
    pub buttons: [u8; 128],
    /// The velocity, acceleration and force axes, unread.
    pub rest: [i32; 24],
}

impl Default for JoyState {
    fn default() -> JoyState {
        JoyState { axes: [0; 6], sliders: [0; 2], pov: [u32::MAX; 4], buttons: [0; 128], rest: [0; 24] }
    }
}

/// FUN_100059c0: the first hat switch as an X axis, with the hat option (padmode000's [3], DAT_10456de5): right
/// between 22.5 and 157.5 degrees, left between 202.5 and 337.5 (hundredths, exclusive).
pub fn pov_x(pov: u32, hat: bool) -> i32 {
    if pov != u32::MAX && hat {
        if 0x8ca < pov && pov < 0x3d86 {
            return 127;
        }
        if 0x4f1a < pov && pov < 0x83d6 {
            return -127;
        }
    }
    0
}

/// FUN_10005a00: the first hat switch as a Y axis (DirectInput's down positive): up under 67.5 or over 292.5 degrees,
/// down between 112.5 and 247.5.
pub fn pov_y(pov: u32) -> i32 {
    if pov != u32::MAX {
        if !(0x1a5e..=0x7242).contains(&pov) {
            return -127;
        }
        if 0x2bf2 < pov && pov < 0x60ae {
            return 127;
        }
    }
    0
}

/// The DirectInput branch's axis codes (jump table 0x10007788): 1 ..= 6 lX, lY, lZ, lRx, lRy, lRz; 7 and 8 the
/// sliders (with padmode000's [2], DAT_10456de6, else 0); 9 and 10 the first hat switch's X and Y (with [3], DAT_10456de5,
/// else 0). Values as DirectInput gives them in the range FUN_100083d0 sets (-127 ..= 127, down positive).
pub fn axis(s: &JoyState, code: u8, sliders: bool, hat: bool) -> i32 {
    match code {
        1..=6 => s.axes[code as usize - 1],
        7 | 8 if sliders => s.sliders[code as usize - 7],
        9 if hat => pov_x(s.pov[0], hat),
        10 if hat => pov_y(s.pov[0]),
        _ => 0,
    }
}

/// The buttons down that padsin numbers (0 ..= 31; rgbButtons' high bit).
pub fn buttons(s: &JoyState) -> Vec<u8> {
    (0..32u8).filter(|&i| s.buttons[i as usize] & 0x80 != 0).collect()
}

/// The movement stick after the DirectInput branch's dead zone (FUN_10005a40, 0x10006753): past a push of
/// sqrt(0x25cd) both values are scaled by (x² + y²) / max(x², y²), then each is held to ±127.
pub fn square(x: i32, y: i32) -> (i32, i32) {
    let (x, y) = (x as i16 as i32, y as i16 as i32);
    let s = x * x + y * y;
    let (mut x, mut y) = (x, y);
    if s > 0x25cd {
        let f = s as f64 / if x.abs() > y.abs() { (x * x) as f64 } else { (y * y) as f64 };
        (x, y) = ((x as f64 * f) as i32, (y as f64 * f) as i32);
    }
    let hold = |v: i32| if v.abs() > 127 { 127 * v.signum() } else { v };
    (hold(x as i16 as i32), hold(y as i16 as i32))
}

/// The constant force FUN_10007ae0 sets on a DirectInput device for a level m (0 ..= 10000): its direction and
/// magnitude. One force axis: direction 0, magnitude m; two: direction (m, m), magnitude sqrt(2 m²) (ftol).
pub fn force(m: i32, axes: u32) -> ([i32; 2], i32) {
    if axes == 1 { ([0, 0], m) } else { ([m, m], ((2.0 * (m as f64) * (m as f64)).sqrt()) as i32) }
}

/// FUN_10008ab0's test on one device instance ID (Win32_PNPEntity DeviceID): an XInput device has "IG_" in it, and
/// its VID_ / PID_ (swscanf "%4X", 0 when absent) are the DirectInput product GUID's Data1 (PID << 16 | VID).
pub fn ig_match(id: &str, product: u32) -> bool {
    if !id.contains("IG_") {
        return false;
    }
    let hex = |key: &str| {
        id.find(key).map_or(0, |i| {
            let digits: String = id[i + key.len()..].chars().take(4).take_while(|c| c.is_ascii_hexdigit()).collect();
            u32::from_str_radix(&digits, 16).unwrap_or(0)
        })
    };
    ((hex("PID_") & 0xffff) << 16 | (hex("VID_") & 0xffff)) == product
}

/// What FUN_100057d0 leaves: the XInput slot (pad +0xc9c, -1 before any) and whether the pad is read through
/// XInput (+0xc99).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Pick {
    pub slot: i32,
    pub xinput: bool,
}

impl Default for Pick {
    fn default() -> Pick {
        Pick { slot: -1, xinput: false }
    }
}

impl Pick {
    /// FUN_100057d0 for one enumerated device `inst`: whether the enumeration goes on. `want` is padguid000;
    /// `xinput` the XInput option as it loaded (+0xc9a); `is_xinput` FUN_10008ab0 (asked only with it); `create` makes
    /// the DirectInput device (+0x90), true when it did.
    pub fn device(
        &mut self,
        want: &Guid,
        inst: &Guid,
        xinput: bool,
        is_xinput: impl FnOnce() -> bool,
        create: impl FnOnce() -> bool,
    ) -> bool {
        if want.is_nil() {
            self.slot = 0;
            if xinput && is_xinput() {
                // The XInput pad at slot 0, and the enumeration goes on: a later DirectInput device is read instead.
                self.xinput = true;
                return true;
            }
            return !create();
        }
        let x = xinput && is_xinput();
        if x {
            self.slot += 1;
        }
        if inst != want {
            return true;
        }
        if x {
            self.xinput = true;
        } else {
            create();
        }
        false
    }
}

/// Whether FUN_100083d0's enumeration would pick something among the `attached` controllers: with no padguid000 any
/// one (the first, DirectInput or XInput), else that one. The rescan runs the setup only then.
pub fn would_pick(want: &Guid, attached: &[Guid]) -> bool {
    if want.is_nil() { !attached.is_empty() } else { attached.contains(want) }
}

/// A controller DirectInput lists (FFXiPadConfig's list: attached game controllers).
#[derive(Clone, Debug, PartialEq)]
pub struct Listed {
    pub guid: Guid,
    pub name: String,
}

#[cfg(windows)]
pub use win::DInput;

#[cfg(windows)]
mod win {
    use super::{Guid, JoyState, Listed, Pick, force, ig_match};
    use std::ffi::c_void;
    use windows_sys::Win32::Devices::DeviceAndDriverInstallation::{
        DIGCF_ALLCLASSES, DIGCF_PRESENT, SP_DEVINFO_DATA, SetupDiDestroyDeviceInfoList, SetupDiEnumDeviceInfo,
        SetupDiGetClassDevsW, SetupDiGetDeviceInstanceIdW,
    };
    use windows_sys::Win32::Devices::HumanInterfaceDevice::{
        DI8DEVCLASS_GAMECTRL, DICONSTANTFORCE, DIDATAFORMAT, DIDEVCAPS, DIDEVICEINSTANCEW, DIDEVICEOBJECTINSTANCEW,
        DIEDFL_ATTACHEDONLY, DIEDFL_FORCEFEEDBACK, DIEFFECT, DIJOYSTATE2, DIOBJECTDATAFORMAT, DIPROPDWORD,
        DIPROPHEADER, DIPROPRANGE, DirectInput8Create, GUID_ConstantForce, GUID_POV, GUID_RxAxis, GUID_RyAxis,
        GUID_RzAxis, GUID_Slider, GUID_XAxis, GUID_YAxis, GUID_ZAxis,
    };
    use windows_sys::Win32::Foundation::HWND;
    use windows_sys::Win32::System::LibraryLoader::GetModuleHandleW;
    use windows_sys::core::{GUID, HRESULT};

    /// IID_IDirectInput8W (retail asks for the A interface, 0x10343064; the devices are the same).
    const IID_IDIRECTINPUT8W: GUID = GUID::from_u128(0xbf798031_483a_4da2_aa99_5d64ed369700);
    /// DIPROP_BUFFERSIZE and DIPROP_RANGE (MAKEDIPROP(1) / (4)).
    const DIPROP_BUFFERSIZE: usize = 1;
    const DIPROP_RANGE: usize = 4;
    const DIPH_BYOFFSET: u32 = 1;
    /// DISCL_EXCLUSIVE | DISCL_FOREGROUND / DISCL_BACKGROUND.
    const DISCL_EXCLUSIVE: u32 = 1;
    const DISCL_FOREGROUND: u32 = 4;
    const DISCL_BACKGROUND: u32 = 8;
    const DIDC_POLLEDDEVICE: u32 = 2;
    const DIDC_POLLEDDATAFORMAT: u32 = 8;
    const DIDFT_AXIS: u32 = 3;
    const DIDOI_FFACTUATOR: u32 = 1;
    const DIEFF_CARTESIAN: u32 = 0x10;
    const DIEFF_OBJECTOFFSETS: u32 = 2;
    const DIEP_DIRECTION: u32 = 0x40;
    const DIEP_TYPESPECIFICPARAMS: u32 = 0x100;
    const DIEP_START: u32 = 0x2000_0000;
    /// DIERR_INPUTLOST, DIERR_NOTACQUIRED, and 0x800700AA: FUN_10005a40 lets the device go on these.
    const LOST: [HRESULT; 3] = [0x8007_001Eu32 as i32, 0x8007_000Cu32 as i32, 0x8007_00AAu32 as i32];

    /// A COM method: the object's vtable slot `i`.
    unsafe fn method(obj: *mut c_void, i: usize) -> usize {
        unsafe { *(*(obj as *const *const usize)).add(i) }
    }

    /// The attached game controllers' instance GUIDs, through an IDirectInput8 of the calling thread's own.
    pub fn attached() -> Vec<Guid> {
        let mut di = std::ptr::null_mut();
        let hr = unsafe {
            DirectInput8Create(
                GetModuleHandleW(std::ptr::null()),
                0x800,
                &IID_IDIRECTINPUT8W,
                &mut di,
                std::ptr::null_mut(),
            )
        };
        if hr < 0 || di.is_null() {
            return Vec::new();
        }
        let mut list = Vec::new();
        let mut ctx = Ctx { pad: std::ptr::null_mut(), want: Guid::default(), list: Some(&mut list) };
        enum_devices(di, DIEDFL_ATTACHEDONLY, &mut ctx);
        unsafe { release(di) };
        list.into_iter().map(|l| l.guid).collect()
    }

    unsafe fn release(obj: *mut c_void) {
        if !obj.is_null() {
            let f: unsafe extern "system" fn(*mut c_void) -> u32 = unsafe { std::mem::transmute(method(obj, 2)) };
            unsafe { f(obj) };
        }
    }

    fn ours(g: &GUID) -> Guid {
        Guid { data1: g.data1, data2: g.data2, data3: g.data3, data4: g.data4 }
    }

    /// c_dfDIJoystick2 (0x1034b23c, 164 objects at 0x103105f0): the axes, the sliders, four hat switches and 128
    /// buttons, then the velocity, acceleration and force axes (each list naming the sliders at 0x18 / 0x1c, as the
    /// library's own does). Static, as DirectInput keeps the pointers.
    struct Format {
        objs: Vec<DIOBJECTDATAFORMAT>,
        _guids: Box<[GUID; 9]>,
    }

    fn joystick2() -> Format {
        let g = Box::new([
            GUID_XAxis,
            GUID_YAxis,
            GUID_ZAxis,
            GUID_RxAxis,
            GUID_RyAxis,
            GUID_RzAxis,
            GUID_Slider,
            GUID_POV,
            GUID::from_u128(0),
        ]);
        let p = |i: usize| if i == 8 { std::ptr::null() } else { &g[i] as *const GUID };
        let mut objs = Vec::with_capacity(164);
        let axis = |objs: &mut Vec<DIOBJECTDATAFORMAT>, base: u32, aspect: u32| {
            for i in 0..6 {
                objs.push(DIOBJECTDATAFORMAT {
                    pguid: p(i),
                    dwOfs: base + 4 * i as u32,
                    dwType: 0x80ff_ff03,
                    dwFlags: aspect,
                });
            }
            for ofs in [0x18, 0x1c] {
                objs.push(DIOBJECTDATAFORMAT { pguid: p(6), dwOfs: ofs, dwType: 0x80ff_ff03, dwFlags: aspect });
            }
        };
        axis(&mut objs, 0, 0x100);
        for i in 0..4 {
            objs.push(DIOBJECTDATAFORMAT { pguid: p(7), dwOfs: 0x20 + 4 * i, dwType: 0x80ff_ff10, dwFlags: 0 });
        }
        for i in 0..128 {
            objs.push(DIOBJECTDATAFORMAT { pguid: p(8), dwOfs: 0x30 + i, dwType: 0x80ff_ff0c, dwFlags: 0 });
        }
        axis(&mut objs, 0xb0, 0x200);
        axis(&mut objs, 0xd0, 0x300);
        axis(&mut objs, 0xf0, 0x400);
        Format { objs, _guids: g }
    }

    /// Retail's pad object, its controller part: the interface, the device (+0x90), its effect (DAT_10456dd8) and
    /// force axes (DAT_10456dd4), the pick (+0xc9c / +0xc99), the XInput option as it loaded (+0xc9a), polling
    /// (+0xc98), the frames since the device was lost (+0xda4) and the last force (+0xdc0).
    pub struct DInput {
        di: *mut c_void,
        dev: *mut c_void,
        effect: *mut c_void,
        ff_axes: u32,
        last_force: i32,
        pub pick: Pick,
        /// The device's instance name.
        pub name: String,
        xinput_loaded: bool,
        polled: bool,
        lost: u32,
        hwnd: HWND,
        /// The rescan's enumeration on its thread (probe), until it answers.
        probe: Option<std::sync::mpsc::Receiver<Vec<Guid>>>,
        /// The data format's objects, kept while `df` points at them.
        _format: Format,
        df: DIDATAFORMAT,
    }

    /// One enumeration's context: the pad (none while listing), padguid000, the list being made.
    struct Ctx<'a> {
        pad: *mut DInput,
        want: Guid,
        list: Option<&'a mut Vec<Listed>>,
    }

    unsafe extern "system" fn callback(inst: *const DIDEVICEINSTANCEW, ctx: *mut c_void) -> i32 {
        let (inst, ctx) = unsafe { (&*inst, &mut *(ctx as *mut Ctx)) };
        if let Some(list) = ctx.list.as_mut() {
            let n = inst.tszInstanceName.iter().position(|&c| c == 0).unwrap_or(inst.tszInstanceName.len());
            let name = String::from_utf16_lossy(&inst.tszInstanceName[..n]);
            list.push(Listed { guid: ours(&inst.guidInstance), name });
            return 1;
        }
        let pad = unsafe { &mut *ctx.pad };
        let mut pick = pad.pick;
        let go = pick.device(
            &ctx.want,
            &ours(&inst.guidInstance),
            pad.xinput_loaded,
            || is_xinput(inst.guidProduct.data1),
            || pad.create(inst),
        );
        pad.pick = pick;
        go as i32
    }

    /// IDirectInput8::EnumDevices over the game controllers.
    fn enum_devices(di: *mut c_void, flags: u32, ctx: &mut Ctx) -> HRESULT {
        type Enum = unsafe extern "system" fn(
            *mut c_void,
            u32,
            unsafe extern "system" fn(*const DIDEVICEINSTANCEW, *mut c_void) -> i32,
            *mut c_void,
            u32,
        ) -> HRESULT;
        unsafe {
            let f: Enum = std::mem::transmute(method(di, 4));
            f(di, DI8DEVCLASS_GAMECTRL, callback, ctx as *mut Ctx as *mut c_void, flags)
        }
    }

    unsafe extern "system" fn count_ff(obj: *const DIDEVICEOBJECTINSTANCEW, n: *mut c_void) -> i32 {
        // FUN_100083b0: the force feedback actuators among the axes.
        if unsafe { (*obj).dwFlags } & DIDOI_FFACTUATOR != 0 {
            unsafe { *(n as *mut u32) += 1 };
        }
        1
    }

    /// FUN_10008ab0: a present Plug and Play device whose instance ID marks it XInput ("IG_") with this product's
    /// VID and PID. *(Retail asks WMI's Win32_PNPEntity for the DeviceIDs; SetupAPI lists the same present devices'
    /// instance IDs.)*
    fn is_xinput(product: u32) -> bool {
        unsafe {
            let set = SetupDiGetClassDevsW(
                std::ptr::null(),
                std::ptr::null(),
                std::ptr::null_mut(),
                DIGCF_ALLCLASSES | DIGCF_PRESENT,
            );
            if set == -1 {
                return false;
            }
            let mut found = false;
            let mut i = 0;
            loop {
                let mut d = SP_DEVINFO_DATA { cbSize: size_of::<SP_DEVINFO_DATA>() as u32, ..std::mem::zeroed() };
                if SetupDiEnumDeviceInfo(set, i, &mut d) == 0 {
                    break;
                }
                i += 1;
                let mut buf = [0u16; 512];
                let mut len = 0u32;
                if SetupDiGetDeviceInstanceIdW(set, &d, buf.as_mut_ptr(), buf.len() as u32, &mut len) != 0 {
                    let n = buf.iter().position(|&c| c == 0).unwrap_or(buf.len());
                    if ig_match(&String::from_utf16_lossy(&buf[..n]), product) {
                        found = true;
                        break;
                    }
                }
            }
            SetupDiDestroyDeviceInfoList(set);
            found
        }
    }

    impl DInput {
        /// FUN_100058f0's DirectInput8Create.
        pub fn new(hwnd: isize) -> Result<Box<DInput>, String> {
            let mut di = std::ptr::null_mut();
            let hr = unsafe {
                DirectInput8Create(
                    GetModuleHandleW(std::ptr::null()),
                    0x800,
                    &IID_IDIRECTINPUT8W,
                    &mut di,
                    std::ptr::null_mut(),
                )
            };
            if hr < 0 || di.is_null() {
                return Err(format!("DirectInput8Create {hr:#x}"));
            }
            let format = joystick2();
            let df = DIDATAFORMAT {
                dwSize: size_of::<DIDATAFORMAT>() as u32,
                dwObjSize: size_of::<DIOBJECTDATAFORMAT>() as u32,
                dwFlags: 1, // DIDF_ABSAXIS
                dwDataSize: size_of::<DIJOYSTATE2>() as u32,
                dwNumObjs: format.objs.len() as u32,
                rgodf: format.objs.as_ptr() as *mut _,
            };
            Ok(Box::new(DInput {
                di,
                dev: std::ptr::null_mut(),
                effect: std::ptr::null_mut(),
                ff_axes: 0,
                last_force: 0,
                pick: Pick::default(),
                name: String::new(),
                xinput_loaded: false,
                polled: false,
                lost: 0,
                hwnd: hwnd as HWND,
                probe: None,
                _format: format,
                df,
            }))
        }

        /// A DirectInput device plays (+0x90).
        pub fn has_device(&self) -> bool {
            !self.dev.is_null()
        }

        /// The attached game controllers, in DirectInput's order (FFXiPadConfig's list, FUN_00404660).
        pub fn list(&mut self) -> Vec<Listed> {
            let mut list = Vec::new();
            let mut ctx = Ctx { pad: std::ptr::null_mut(), want: Guid::default(), list: Some(&mut list) };
            enum_devices(self.di, DIEDFL_ATTACHEDONLY, &mut ctx);
            list
        }

        /// FUN_100083d0: the controller from padguid000 (`want`). `xinput`: the XInput option and whether retail's
        /// XInput DLL loaded (FUN_10008d90); `rumble` the force feedback option; `background` padmode000's [4].
        pub fn setup(&mut self, want: &Guid, xinput: Option<bool>, rumble: bool, background: bool) {
            // The XInput option: +0xc9a as the DLL loaded, and nothing more when it did not. Without the option
            // +0xc9a keeps what it was (retail never clears it).
            if let Some(loaded) = xinput {
                self.xinput_loaded = loaded;
                if !loaded {
                    return;
                }
            }
            self.close();
            // The force feedback devices first with the rumble option; the effect is made only for a device that
            // pass found ([esp+0x13], cleared by the second pass).
            let (di, me) = (self.di, self as *mut DInput);
            let mut ff = true;
            let mut hr = 0;
            if rumble {
                let mut ctx = Ctx { pad: me, want: *want, list: None };
                hr = enum_devices(di, DIEDFL_ATTACHEDONLY | DIEDFL_FORCEFEEDBACK, &mut ctx);
            }
            if !rumble || hr < 0 || self.dev.is_null() {
                ff = false;
                let mut ctx = Ctx { pad: me, want: *want, list: None };
                hr = enum_devices(di, DIEDFL_ATTACHEDONLY, &mut ctx);
            }
            if hr < 0 || self.dev.is_null() {
                self.dev = std::ptr::null_mut();
                return;
            }
            log::info!("gamepad (DirectInput): controller opened (padguid000 {})", want.text());
            self.configure(ff && rumble, background);
        }

        /// CreateDevice into +0x90 (FUN_100057d0).
        fn create(&mut self, inst: &DIDEVICEINSTANCEW) -> bool {
            type Create = unsafe extern "system" fn(*mut c_void, *const GUID, *mut *mut c_void, *mut c_void) -> HRESULT;
            let mut dev = std::ptr::null_mut();
            let hr = unsafe {
                let f: Create = std::mem::transmute(method(self.di, 3));
                f(self.di, &inst.guidInstance, &mut dev, std::ptr::null_mut())
            };
            if hr < 0 {
                return false;
            }
            self.dev = dev;
            let n = inst.tszInstanceName.iter().position(|&c| c == 0).unwrap_or(inst.tszInstanceName.len());
            self.name = String::from_utf16_lossy(&inst.tszInstanceName[..n]);
            true
        }

        /// FUN_100083d0 after the enumeration: caps (polling), the buffer, the data format, the cooperative level,
        /// each axis's range ±127, Acquire, then the force feedback effect.
        fn configure(&mut self, ff: bool, background: bool) {
            let dev = self.dev;
            type Caps = unsafe extern "system" fn(*mut c_void, *mut DIDEVCAPS) -> HRESULT;
            type SetProp = unsafe extern "system" fn(*mut c_void, usize, *const DIPROPHEADER) -> HRESULT;
            type SetFormat = unsafe extern "system" fn(*mut c_void, *const DIDATAFORMAT) -> HRESULT;
            type Coop = unsafe extern "system" fn(*mut c_void, HWND, u32) -> HRESULT;
            type Plain = unsafe extern "system" fn(*mut c_void) -> HRESULT;
            unsafe {
                let mut caps: DIDEVCAPS = std::mem::zeroed();
                caps.dwSize = size_of::<DIDEVCAPS>() as u32;
                (std::mem::transmute::<usize, Caps>(method(dev, 3)))(dev, &mut caps);
                self.polled = caps.dwFlags & (DIDC_POLLEDDEVICE | DIDC_POLLEDDATAFORMAT) != 0;
                let set_prop: SetProp = std::mem::transmute(method(dev, 6));
                let header = |size: usize, obj: u32, how: u32| DIPROPHEADER {
                    dwSize: size as u32,
                    dwHeaderSize: size_of::<DIPROPHEADER>() as u32,
                    dwObj: obj,
                    dwHow: how,
                };
                let buffer = DIPROPDWORD { diph: header(size_of::<DIPROPDWORD>(), 0, 0), dwData: 0x140 };
                if set_prop(dev, DIPROP_BUFFERSIZE, &buffer.diph) < 0 {
                    return self.fail();
                }
                let df = &self.df as *const DIDATAFORMAT;
                if (std::mem::transmute::<usize, SetFormat>(method(dev, 11)))(dev, df) < 0 {
                    return self.fail();
                }
                let level = DISCL_EXCLUSIVE | if background { DISCL_BACKGROUND } else { DISCL_FOREGROUND };
                if (std::mem::transmute::<usize, Coop>(method(dev, 13)))(dev, self.hwnd, level) < 0 {
                    return self.fail();
                }
                for ofs in (0..0x20).step_by(4) {
                    let r = DIPROPRANGE {
                        diph: header(size_of::<DIPROPRANGE>(), ofs, DIPH_BYOFFSET),
                        lMin: -127,
                        lMax: 127,
                    };
                    set_prop(dev, DIPROP_RANGE, &r.diph);
                }
                (std::mem::transmute::<usize, Plain>(method(dev, 7)))(dev);
                if !ff {
                    return;
                }
                type EnumObjs = unsafe extern "system" fn(
                    *mut c_void,
                    unsafe extern "system" fn(*const DIDEVICEOBJECTINSTANCEW, *mut c_void) -> i32,
                    *mut c_void,
                    u32,
                ) -> HRESULT;
                self.ff_axes = 0;
                let n = &mut self.ff_axes as *mut u32 as *mut c_void;
                if (std::mem::transmute::<usize, EnumObjs>(method(dev, 4)))(dev, count_ff, n, DIDFT_AXIS) < 0 {
                    return;
                }
                self.ff_axes = self.ff_axes.min(2);
                let mut axes = [0u32, 4];
                let mut dir = [0i32, 0];
                let mut cf = DICONSTANTFORCE { lMagnitude: 0 };
                let eff = DIEFFECT {
                    dwSize: size_of::<DIEFFECT>() as u32,
                    dwFlags: DIEFF_CARTESIAN | DIEFF_OBJECTOFFSETS,
                    dwDuration: u32::MAX,
                    dwSamplePeriod: 0,
                    dwGain: 10000,
                    dwTriggerButton: u32::MAX,
                    dwTriggerRepeatInterval: 0,
                    cAxes: self.ff_axes,
                    rgdwAxes: axes.as_mut_ptr(),
                    rglDirection: dir.as_mut_ptr(),
                    lpEnvelope: std::ptr::null_mut(),
                    cbTypeSpecificParams: 4,
                    lpvTypeSpecificParams: &mut cf as *mut _ as *mut c_void,
                    dwStartDelay: 0,
                };
                type CreateEffect = unsafe extern "system" fn(
                    *mut c_void,
                    *const GUID,
                    *const DIEFFECT,
                    *mut *mut c_void,
                    *mut c_void,
                ) -> HRESULT;
                let mut e = std::ptr::null_mut();
                if (std::mem::transmute::<usize, CreateEffect>(method(dev, 18)))(
                    dev,
                    &GUID_ConstantForce,
                    &eff,
                    &mut e,
                    std::ptr::null_mut(),
                ) >= 0
                {
                    self.effect = e;
                }
            }
        }

        /// FUN_10008770: a setup step failed, the device goes.
        fn fail(&mut self) {
            self.close();
        }

        /// The effect unloaded and released, the device unacquired and released (FUN_10005720 / the loss paths).
        fn close(&mut self) {
            unsafe {
                if !self.effect.is_null() {
                    let unload: unsafe extern "system" fn(*mut c_void) -> HRESULT =
                        std::mem::transmute(method(self.effect, 11));
                    unload(self.effect);
                    release(self.effect);
                    self.effect = std::ptr::null_mut();
                }
                if !self.dev.is_null() {
                    let unacquire: unsafe extern "system" fn(*mut c_void) -> HRESULT =
                        std::mem::transmute(method(self.dev, 8));
                    unacquire(self.dev);
                    release(self.dev);
                    self.dev = std::ptr::null_mut();
                }
            }
            self.last_force = 0;
        }

        /// DAT_10456df0 (padguid000 or the options changed): the device goes, the pick starts over, and the
        /// enumeration runs again at once with the pad on.
        pub fn reset(&mut self) {
            self.close();
            self.pick = Pick::default();
            self.probe = None;
        }

        /// FUN_100087d0 on WM_ACTIVATE: the device is acquired again (it fails in the background unless
        /// DISCL_BACKGROUND).
        pub fn acquire(&mut self) {
            if !self.dev.is_null() {
                unsafe {
                    let f: unsafe extern "system" fn(*mut c_void) -> HRESULT = std::mem::transmute(method(self.dev, 7));
                    f(self.dev);
                }
            }
        }

        /// The rescan's enumeration (FUN_100083d0's EnumDevices), on a thread of its own with its own DirectInput
        /// interface: EnumDevices can take tens to hundreds of milliseconds. *(Not retail: retail enumerates on its
        /// frame; the timing is retail's, the setup runs on the frame only once a controller it would pick is
        /// attached (would_pick).)*
        pub fn probe(&mut self) {
            if self.probe.is_none() {
                let (tx, rx) = std::sync::mpsc::channel();
                std::thread::spawn(move || {
                    let _ = tx.send(attached());
                });
                self.probe = Some(rx);
            }
        }

        /// The probe's answer, once it is in.
        pub fn probed(&mut self) -> Option<Vec<Guid>> {
            let found = self.probe.as_ref()?.try_recv();
            match found {
                Ok(v) => {
                    self.probe = None;
                    Some(v)
                }
                Err(std::sync::mpsc::TryRecvError::Disconnected) => {
                    self.probe = None;
                    None
                }
                Err(std::sync::mpsc::TryRecvError::Empty) => None,
            }
        }

        /// FUN_10005a40 with no device: the frames since it was lost; true on the 0x5b-th, when FUN_100083d0 runs
        /// again (the count starts over).
        pub fn lost_frame(&mut self) -> bool {
            self.lost += 1;
            if self.lost > 0x5a {
                self.lost = 0;
                return true;
            }
            false
        }

        /// FUN_10005a40's DirectInput branch: Poll when the device asks for it, then GetDeviceState. A lost device
        /// is let go (None); any other failure reads nothing this frame.
        pub fn read(&mut self) -> Option<JoyState> {
            let dev = self.dev;
            if dev.is_null() {
                return None;
            }
            let mut s = JoyState::default();
            let hr = unsafe {
                if self.polled {
                    let poll: unsafe extern "system" fn(*mut c_void) -> HRESULT = std::mem::transmute(method(dev, 25));
                    poll(dev);
                }
                type State = unsafe extern "system" fn(*mut c_void, u32, *mut c_void) -> HRESULT;
                let f: State = std::mem::transmute(method(dev, 9));
                f(dev, size_of::<JoyState>() as u32, &mut s as *mut JoyState as *mut c_void)
            };
            if LOST.contains(&hr) {
                log::info!("gamepad (DirectInput): device lost ({hr:#x})");
                self.close();
                return None;
            }
            Some(if hr == 0 { s } else { JoyState::default() })
        }

        /// FUN_10007ae0's DirectInput branch, once the hold lets it: the constant force for level `m` (0 ..= 10000),
        /// started; nothing when it and the last one are 0.
        pub fn force(&mut self, m: i32) {
            if self.effect.is_null() {
                return;
            }
            let (mut dir, mag) = force(m, self.ff_axes);
            if mag == 0 && self.last_force == 0 {
                return;
            }
            self.last_force = mag;
            let mut cf = DICONSTANTFORCE { lMagnitude: mag };
            unsafe {
                let mut eff: DIEFFECT = std::mem::zeroed();
                eff.dwSize = size_of::<DIEFFECT>() as u32;
                eff.dwFlags = DIEFF_CARTESIAN | DIEFF_OBJECTOFFSETS;
                eff.cAxes = self.ff_axes;
                eff.rglDirection = dir.as_mut_ptr();
                eff.cbTypeSpecificParams = 4;
                eff.lpvTypeSpecificParams = &mut cf as *mut _ as *mut c_void;
                type Set = unsafe extern "system" fn(*mut c_void, *const DIEFFECT, u32) -> HRESULT;
                let f: Set = std::mem::transmute(method(self.effect, 6));
                f(self.effect, &eff, DIEP_START | DIEP_TYPESPECIFICPARAMS | DIEP_DIRECTION);
            }
        }
    }

    impl Drop for DInput {
        fn drop(&mut self) {
            self.close();
            unsafe { release(self.di) };
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The rescan sets up only when the pick would find something: any controller without padguid000, else it.
    #[test]
    fn rescan_picks() {
        let g = Guid::parse("{55DDF31E-8F9C-11F1-8001-000044455354}");
        let other = Guid::parse("{00000001-0000-0000-0000-000000000000}");
        assert!(!would_pick(&Guid::default(), &[]));
        assert!(would_pick(&Guid::default(), &[other]));
        assert!(!would_pick(&g, &[other]));
        assert!(would_pick(&g, &[other, g]));
    }

    #[test]
    fn guid_text_round_trip() {
        let s = "{55DDF31E-8F9C-11F1-8001-000044455354}";
        let g = Guid::parse(s);
        assert_eq!((g.data1, g.data2, g.data3), (0x55ddf31e, 0x8f9c, 0x11f1));
        assert_eq!(g.data4, [0x80, 0x01, 0, 0, 0x44, 0x45, 0x53, 0x54]);
        assert_eq!(g.text(), s);
        assert!(Guid::parse("").is_nil());
        assert!(Guid::parse("{55DDF31E-8F9C-11F1-8001-00004445535}").is_nil());
        assert_eq!(Guid::parse(&s.to_lowercase()), g);
    }

    /// The hat as axes 9 and 10: the eight directions, centred, and X without the hat option.
    #[test]
    fn hat_switch() {
        let at = |deg: u32| (pov_x(deg * 100, true), pov_y(deg * 100));
        assert_eq!(at(0), (0, -127));
        assert_eq!(at(45), (127, -127));
        assert_eq!(at(90), (127, 0));
        assert_eq!(at(135), (127, 127));
        assert_eq!(at(180), (0, 127));
        assert_eq!(at(225), (-127, 127));
        assert_eq!(at(270), (-127, 0));
        assert_eq!(at(315), (-127, -127));
        assert_eq!((pov_x(u32::MAX, true), pov_y(u32::MAX)), (0, 0));
        assert_eq!(pov_x(9000, false), 0);
        // The edges are exclusive: 22.5 degrees is still only up.
        assert_eq!((pov_x(0x8ca, true), pov_y(0x8ca)), (0, -127));
    }

    #[test]
    fn axis_codes() {
        let s = JoyState { axes: [1, 2, 3, 4, 5, 6], sliders: [7, 8], pov: [9000, 0, 0, 0], ..Default::default() };
        let all: Vec<i32> = (1..=10).map(|c| axis(&s, c, true, true)).collect();
        assert_eq!(all, [1, 2, 3, 4, 5, 6, 7, 8, 127, 0]);
        let off: Vec<i32> = (1..=10).map(|c| axis(&s, c, false, false)).collect();
        assert_eq!(off, [1, 2, 3, 4, 5, 6, 0, 0, 0, 0]);
        assert_eq!((axis(&s, 0, true, true), axis(&s, 11, true, true)), (0, 0));
    }

    #[test]
    fn buttons_down() {
        let mut s = JoyState::default();
        (s.buttons[0], s.buttons[5], s.buttons[31], s.buttons[32], s.buttons[2]) = (0x80, 0x80, 0xff, 0x80, 0x7f);
        assert_eq!(buttons(&s), vec![0, 5, 31]);
    }

    /// Under the push nothing changes; a diagonal goes out to the corner, a straight push stays, both held to 127.
    #[test]
    fn movement_square() {
        assert_eq!(square(60, 60), (60, 60));
        assert_eq!(square(90, 90), (127, 127));
        assert_eq!(square(100, 0), (100, 0));
        assert_eq!(square(-127, 0), (-127, 0));
        // 100² + 50² = 12500 over 100²: x 125, y 62 (ftol).
        assert_eq!(square(100, 50), (125, 62));
        assert_eq!(square(-100, -50), (-125, -62));
    }

    #[test]
    fn force_axes() {
        assert_eq!(force(1000, 1), ([0, 0], 1000));
        assert_eq!(force(1000, 2), ([1000, 1000], 1414));
        assert_eq!(force(0, 2), ([0, 0], 0));
    }

    #[test]
    fn xinput_device_ids() {
        // Xbox 360 pad (VID 045E, PID 028E): guidProduct.Data1 = 0x028E045E.
        let id = r"HID\VID_045E&PID_028E&IG_00\3&2A8BE9F6&0&0000";
        assert!(ig_match(id, 0x028e045e));
        assert!(!ig_match(id, 0x02ea045e));
        assert!(!ig_match(r"HID\VID_045E&PID_028E\3&2A8BE9F6&0&0000", 0x028e045e));
        assert!(!ig_match(r"USB\VID_054C&PID_09CC\5&1", 0x09cc054c));
    }

    /// FUN_100057d0 over a device list: X1, D1, X2, D2 (XInput or DirectInput), the XInput option on.
    #[test]
    fn picks() {
        let g = |n: u32| Guid { data1: n, ..Default::default() };
        let devs = [(g(1), true), (g(2), false), (g(3), true), (g(4), false)];
        let run = |want: Guid, xinput: bool| {
            let mut p = Pick::default();
            let mut created = None;
            for (inst, x) in devs {
                if !p.device(
                    &want,
                    &inst,
                    xinput,
                    || x,
                    || {
                        created = Some(inst.data1);
                        true
                    },
                ) {
                    break;
                }
            }
            (p, created)
        };
        // No padguid: X1 is XInput slot 0, and D1 is created too (the DirectInput device is the one read).
        assert_eq!(run(Guid::default(), true), (Pick { slot: 0, xinput: true }, Some(2)));
        // padguid X2: the second XInput pad, slot 1, nothing created.
        assert_eq!(run(g(3), true), (Pick { slot: 1, xinput: true }, None));
        // padguid D2: created; the slot counts the XInput pads passed.
        assert_eq!(run(g(4), true), (Pick { slot: 1, xinput: false }, Some(4)));
        // XInput option off: every pad through DirectInput.
        assert_eq!(run(g(3), false), (Pick { slot: -1, xinput: false }, Some(3)));
        assert_eq!(run(Guid::default(), false), (Pick { slot: 0, xinput: false }, Some(1)));
        // padguid not attached: nothing.
        assert_eq!(run(g(9), true), (Pick { slot: 1, xinput: false }, None));
    }
}
