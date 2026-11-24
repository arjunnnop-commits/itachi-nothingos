mod power_state;
mod panel_writes;
static PANEL_WRITES: panel_writes::PanelWrites = panel_writes::PanelWrites::new();
use power_state::{parse_power_state, PowerState};

use std::{
    fs::{self, File, OpenOptions},
    io::{BufRead, BufReader, Read, Write},
    process::{Command, Stdio},
    sync::OnceLock,
    thread,
    time::Duration,
};

use base64::{engine::general_purpose::STANDARD, Engine};
use ed25519_dalek::{Signature, VerifyingKey};
use sha2::{Digest, Sha256};

const SYSTEM_PROP: &str = "/system/build.prop";
const AUTH_NAME: &str = "ro.itachi.aod.auth";

const SENSOR_HAL: &str = "/vendor/lib64/hw/sensors.mt6897.so";
const AOD_DAEMON: &str = "/system/bin/itachi_aodd";
const FOD_COMPAT: &str = "/vendor/lib64/libduchamp_fp_compat.so";



const PUBLIC_KEY: [u8; 32] = [
    0x5d, 0xab, 0x9c, 0x2a, 0x58, 0xf1, 0x09, 0x29,
    0xdc, 0x02, 0x2a, 0x42, 0xee, 0xbe, 0xac, 0xdd,
    0x4b, 0x7d, 0xd8, 0xbe, 0xaf, 0xc1, 0x2a, 0x25,
    0xc8, 0x90, 0x51, 0x5d, 0xf9, 0xaf, 0xa3, 0x29,
];

// duchamp: the rodin `backlight` node does not exist on this panel (mi_display exposes
// brightness_clone / doze_brightness instead). The path and levels are resolved at runtime.
// Overrides: persist.itachi.bl_path, persist.itachi.aod_bl, persist.itachi.fp_bl.
const BL_CANDIDATES: [&str; 2] = [
    "/sys/devices/virtual/mi_display/disp_feature/disp-DSI-0/backlight",
    "/sys/devices/virtual/mi_display/disp_feature/disp-DSI-0/brightness_clone",
];

fn get_prop(name: &str) -> Option<String> {
    let out = Command::new("/system/bin/getprop").arg(name).output().ok()?;
    let value = String::from_utf8_lossy(&out.stdout).trim().to_string();
    if value.is_empty() { None } else { Some(value) }
}

// ro.itachi.rom=nothing -> AOSP-based Nothing OS (no Oplus Setting_Aod* keys).
fn nothing_mode() -> bool {
    static MODE: OnceLock<bool> = OnceLock::new();
    *MODE.get_or_init(|| get_prop("ro.itachi.rom").as_deref() == Some("nothing"))
}

fn bl_path() -> String {
    static OVERRIDE: OnceLock<Option<String>> = OnceLock::new();
    if let Some(path) = OVERRIDE.get_or_init(|| get_prop("persist.itachi.bl_path")) {
        return path.clone();
    }
    for candidate in BL_CANDIDATES {
        if std::path::Path::new(candidate).exists() {
            return candidate.to_string();
        }
    }
    BL_CANDIDATES[0].to_string()
}

fn aod_bl() -> u32 {
    static V: OnceLock<u32> = OnceLock::new();
    *V.get_or_init(|| get_prop("persist.itachi.aod_bl").and_then(|v| v.parse().ok()).unwrap_or(28))
}

fn fp_bl() -> u32 {
    static V: OnceLock<u32> = OnceLock::new();
    *V.get_or_init(|| get_prop("persist.itachi.fp_bl").and_then(|v| v.parse().ok()).unwrap_or(100))
}

fn klog(msg: &str) {
    let _ = Command::new("/system/bin/log")
        .args(["-t", "ItachiAodD", msg])
        .status();

    println!("ItachiAodD: {msg}");
}

fn sha256_bytes(data: &[u8]) -> String {
    let mut h = Sha256::new();
    h.update(data);
    format!("{:x}", h.finalize())
}

fn sha256_file(path: &str) -> Result<String, String> {
    let mut f = File::open(path).map_err(|e| format!("open {path}: {e}"))?;
    let mut h = Sha256::new();
    let mut buf = [0u8; 65536];

    loop {
        let n = f.read(&mut buf).map_err(|e| format!("read {path}: {e}"))?;
        if n == 0 {
            break;
        }
        h.update(&buf[..n]);
    }

    Ok(format!("{:x}", h.finalize()))
}

fn canonical_system_prop() -> Result<(String, String), String> {
    let raw = fs::read_to_string(SYSTEM_PROP)
        .map_err(|e| format!("cannot read {SYSTEM_PROP}: {e}"))?;

    let auth = raw
        .lines()
        .find_map(|line| line.strip_prefix(&format!("{AUTH_NAME}=")))
        .ok_or_else(|| format!("{AUTH_NAME} missing from {SYSTEM_PROP}"))?
        .trim()
        .to_string();

    let mut canonical = String::new();

    for line in raw.lines() {
        if line.starts_with(&format!("{AUTH_NAME}=")) {
            continue;
        }

        canonical.push_str(line);
        canonical.push('\n');
    }

    Ok((auth, sha256_bytes(canonical.as_bytes())))
}

fn authorize() -> Result<(), String> {
    let (value, buildprop_hash) = canonical_system_prop()?;

    let mut parts = value.splitn(3, '.');

    let version = parts.next().ok_or("missing authorization version")?;
    let rom_id = parts.next().ok_or("missing ROM ID")?;
    let encoded_signature = parts.next().ok_or("missing signature")?;

    if version != "ITACHI4" {
        return Err("wrong authorization version".into());
    }

    if rom_id.len() != 64 || !rom_id.bytes().all(|b| b.is_ascii_hexdigit()) {
        return Err("invalid ROM ID".into());
    }

    let hal_hash = sha256_file(SENSOR_HAL)?;
    let aod_hash = sha256_file(AOD_DAEMON)?;
    let fod_hash = sha256_file(FOD_COMPAT)?;

    let manifest = format!(
        "ITACHI_DUCHAMP_SHARED_V4\n\
ROM_ID={}\n\
SYSTEM_BUILD_PROP_SHA256={}\n\
SENSOR_HAL_SHA256={}\n\
AOD_DAEMON_SHA256={}\n\
FOD_COMPAT_SHA256={}",
        rom_id, buildprop_hash, hal_hash, aod_hash, fod_hash
    );

    let decoded = STANDARD
        .decode(encoded_signature)
        .map_err(|_| "bad signature base64")?;

    let sig_bytes: [u8; 64] = decoded
        .try_into()
        .map_err(|_| "wrong signature length")?;

    let key = VerifyingKey::from_bytes(&PUBLIC_KEY)
        .map_err(|_| "bad embedded public key")?;

    let signature = Signature::from_bytes(&sig_bytes);

    key.verify_strict(manifest.as_bytes(), &signature)
        .map_err(|_| "ROM signature mismatch")?;

    Ok(())
}

fn set_prop(name: &str, value: &str) {
    let _ = Command::new("/system/bin/setprop")
        .args([name, value])
        .status();
}

fn settings_get(name: &str) -> Option<String> {
    let out = Command::new("/system/bin/settings")
        .args(["get", "secure", name])
        .output()
        .ok()?;

    Some(String::from_utf8_lossy(&out.stdout).trim().to_string())
}

fn settings_put_sync(name: &str, value: &str) {
    if nothing_mode() && name.starts_with("Setting_Aod") { return; }
    let _ = Command::new("/system/bin/settings")
        .args(["put", "secure", name, value])
        .status();
}

fn settings_put_async(name: &'static str, value: &'static str) {
    if nothing_mode() && name.starts_with("Setting_Aod") { return; }
    thread::spawn(move || {
        let _ = Command::new("/system/bin/settings")
            .args(["put", "secure", name, value])
            .status();
    });
}


fn commit_backlight(value: u32) {
    if let Ok(mut f) = OpenOptions::new().write(true).open(bl_path()) {
        if let Err(error) = write!(f, "{value}") {
            klog(&format!("Panel override failed: {error}"));
        }
    }
}

fn write_backlight(value: u32) {
    let ticket = PANEL_WRITES.invalidate();
    PANEL_WRITES.apply(ticket, || {
        if read_backlight() == Some(value) { return false; }
        // A wake arriving during this query invalidates the result before writing.
        if !read_power_state().permits_panel_override() {
            klog("Panel override skipped: display is interactive or state is unavailable");
            return false;
        }
        true
    }, || commit_backlight(value));
}

fn read_backlight() -> Option<u32> {
    fs::read_to_string(bl_path())
        .ok()?
        .trim()
        .parse::<u32>()
        .ok()
}

fn ensure_aod_backlight(ticket: u64) {
    PANEL_WRITES.apply(ticket, || {
        read_backlight() == Some(0) && read_power_state().permits_panel_override()
    }, || {
        commit_backlight(aod_bl());
        klog("AOD backlight recovery requested");
    });
}

fn read_power_state() -> PowerState {
    let output = match Command::new("/system/bin/timeout")
        .args(["2", "/system/bin/dumpsys", "-t", "1", "power"])
        .output()
    {
        Ok(output) if output.status.success() => output,
        _ => return PowerState::Unknown,
    };
    parse_power_state(&String::from_utf8_lossy(&output.stdout))
}

fn display_really_awake() -> bool {
    !read_power_state().permits_panel_override()
}

fn is_aod_master_enabled() -> bool {
    if nothing_mode() {
        return settings_get("doze_always_on").map(|v| v == "1").unwrap_or(false);
    }
    settings_get("Setting_AodSwitchEnable")
        .map(|v| v == "1")
        .unwrap_or(false)
}

fn is_all_day_aod() -> bool {
    if !is_aod_master_enabled() {
        return false;
    }
    // AOSP AOD has no energy-saving / immediate sub-modes: enabled == all day.
    if nothing_mode() {
        return true;
    }
    let energy = settings_get("Setting_AodUserEnergySavingSet").unwrap_or_default();
    let imm = settings_get("Setting_AodEnableImmediate").unwrap_or_default();
    energy == "0" && imm == "1"
}


// EVONIX_TEST6_SCHEDULED_AOD: Read active ColorOS scheduled-AOD window.
// This is evaluated only on a power-saving hide event, not continuously.
fn aod_schedule_minute(hour_key: &str, minute_key: &str) -> Option<u32> {
    let hour = settings_get(hour_key)?.parse::<u32>().ok()?;
    let minute = settings_get(minute_key)?.parse::<u32>().ok()?;
    if hour > 23 || minute > 59 {
        return None;
    }
    Some(hour * 60 + minute)
}

fn aod_scheduled_now() -> bool {
    if nothing_mode() {
        return false;
    }
    if !is_aod_master_enabled()
        || settings_get("Setting_AodUserSetTime").as_deref() != Some("1")
        || settings_get("Setting_AodEnableImmediate").as_deref() != Some("0")
        || settings_get("Setting_AodUserEnergySavingSet").as_deref() != Some("0")
    {
        return false;
    }
    let Some(start) = aod_schedule_minute(
        "Setting_AodSetTimeBeginHour", "Setting_AodSetTimeBeginMin") else {
        return false;
    };
    let Some(end) = aod_schedule_minute(
        "Setting_AodSetTimeEndHour", "Setting_AodSetTimeEndMin") else {
        return false;
    };
    // Do not reinterpret an equal start/end as a full-day schedule.
    if start == end {
        return false;
    }
    let output = match Command::new("/system/bin/date").arg("+%H:%M").output() {
        Ok(v) if v.status.success() => v,
        _ => return false,
    };
    let local_time = String::from_utf8_lossy(&output.stdout);
    let Some((hour, minute)) = local_time.trim().split_once(':') else {
        return false;
    };
    let (Ok(hour), Ok(minute)) = (hour.parse::<u32>(), minute.parse::<u32>()) else {
        return false;
    };
    if hour > 23 || minute > 59 {
        return false;
    }
    let now = hour * 60 + minute;
    if start < end {
        start <= now && now < end
    } else {
        // Supports overnight intervals such as 23:00 -> 01:00.
        now >= start || now < end
    }
}

fn main() {
    let verify_only = std::env::args().any(|arg| arg == "--verify-only");

    match authorize() {
        Ok(_) => {
            if verify_only {
                klog("V4 shared authorization OK (verify-only)");
                return;
            }
            klog("V4 shared authorization OK");
        }
        Err(e) => {
            klog(&format!("AUTH NOTICE: {e}"));
            if verify_only {
                std::process::exit(73);
            }
            klog("Continuing in shared daemon mode");
        }
    }

    set_prop("sys.itachi4.authorized", "1");
    set_prop("ro.itachi.fod.compat", "1");
    set_prop("persist.sys.duchamp.aod_keep_doze", "1");

    // duchamp: never block forever if the panel node is missing; give up after ~2 minutes.
    let mut bl_wait = 0u32;
    while !std::path::Path::new(&bl_path()).exists() && bl_wait < 240 {
        thread::sleep(Duration::from_millis(500));
        bl_wait += 1;
    }

    let aod_enabled = is_aod_master_enabled();
    klog(&format!("started AOD={} FP={} BL={} (ready)", aod_bl(), fp_bl(), bl_path()));

    let mut pending_energy_hide = false;
    let mut energy_hide_active = false;
    let mut fp_only_phase = !aod_enabled;
    let mut fp_panel_allowed = !aod_enabled;
    let mut tap_clock_active = false;

    if nothing_mode() {
        // AOSP has no "performAodUpdate"/"DOZE_SUSPEND" lines: keep the AOD level alive by polling.
        thread::spawn(|| loop {
            thread::sleep(Duration::from_millis(1000));
            if read_backlight() == Some(0) && is_aod_master_enabled() {
                let ticket = PANEL_WRITES.current();
                ensure_aod_backlight(ticket);
            }
        });
    }

    loop {
        let mut child = match Command::new("/system/bin/logcat")
            .args(["-b", "all", "-v", "brief", "-T", "1"])
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()
        {
            Ok(c) => c,
            Err(e) => {
                klog(&format!("cannot start logcat: {e}"));
                thread::sleep(Duration::from_secs(1));
                continue;
            }
        };

        let stdout = match child.stdout.take() {
            Some(s) => s,
            None => {
                thread::sleep(Duration::from_secs(1));
                continue;
            }
        };

        for result in BufReader::new(stdout).lines() {
            let line = match result {
                Ok(v) => v,
                Err(_) => continue,
            };

            if (line.contains("setScreenState changed:") && line.contains("->ON"))
                || line.contains("Waking up from")
            {
                PANEL_WRITES.invalidate();
                fp_panel_allowed = false;
                pending_energy_hide = false;
                tap_clock_active = false;
            }

            // The framework restores clock content only for a real hardware tap
            // after checking the AOD preference, schedule and proximity. Carry
            // that confirmed state through DOZE entry instead of rereading two
            // settings processes while the native clock is being drawn.
            if line.contains("DuchampAodTapBridge")
                && line.contains("AOD clock content restored for hardware tap")
            {
                tap_clock_active = true;
                fp_only_phase = false;
                pending_energy_hide = false;
                energy_hide_active = false;
                fp_panel_allowed = true;
            }

            // 1. DOZE ENTRY (Normal AOD clock start)
            if line.contains("setScreenState changed:")
                && line.contains("->DOZE")
                && !fp_only_phase
            {
                let ticket = PANEL_WRITES.current();
                thread::spawn(move || {
                    thread::sleep(Duration::from_millis(150));
                    ensure_aod_backlight(ticket);
                });
            }

            // 2. ALL-DAY AOD KEEPALIVE
            // ColorOS wakes into DOZE for time updates then requests DOZE_SUSPEND.
            if !fp_only_phase {
                if line.contains("Final-state=DOZE_SUSPEND") || line.contains("performAodUpdate") {
                    if read_backlight() == Some(0) {
                        write_backlight(aod_bl());
                        klog("AOD keepalive -> hold panel 28");
                    }
                }
            }

            // 3. POWER-SAVING (10s/smart) TIMEOUT HIDE
            if line.contains("WorkshopAodController-->onEnergySavingNotifyHide")
                // EVONIX_TEST6_SCHEDULED_AOD: a status message saying the
                // energy-saving mode is CLOSED must never be treated as an
                // instruction to disable the AOD switch.
                && !line.contains("energySaving mode is closed")
                && !fp_only_phase
            {
                if !is_all_day_aod() && !aod_scheduled_now() {
                    tap_clock_active = false;
                    pending_energy_hide = true;
                    energy_hide_active = true;
                    // CRITICAL: Immediately disable AOD switch in background!
                    // This ensures ColorOS enters Screen-Off Fingerprint (SOFOD) mode
                    // before the screen reaches OFF, eliminating any race condition on instant pickup.
                    settings_put_async("Setting_AodSwitchEnable", "0");
                    fp_only_phase = true;
                    fp_panel_allowed = true;
                    klog("power-saving AOD hide -> armed SOFOD (Setting_AodSwitchEnable=0)");
                } else {
                    klog("EVONIX_TEST6_SCHEDULED_AOD: ignore hide (all-day or scheduled window active)");
                }
            }

            // 4. TRANSITION TO OFF (Screen goes completely off)
            if line.contains("setScreenState changed:DOZE->OFF")
                && (pending_energy_hide || fp_only_phase)
            {
                pending_energy_hide = false;
                fp_only_phase = true;
                fp_panel_allowed = true;
                write_backlight(0);
                klog("entered FP-only phase (screen OFF, panel 0)");
            }

            // The user can change AOD mode without restarting this daemon.
            // Refresh the screen-off ownership only on real wake/display events.
            let hint_wake = line.contains("notifyWakeUpCallback")
                || line.contains("DuchampSensorCompat: instant pickup trigger")
                || line.contains("DuchampSensorCompat: pickup -> synthetic 65611");
            // NothingOS (AOSP PowerManagerService) logs "Going to sleep due to ..."
            // when the screen leaves interactive state; ColorOS-only strings never appear.
            let pms_sleep = nothing_mode() && line.contains("Going to sleep due to");
            let screen_off_transition = pms_sleep
                || (line.contains("setScreenState changed:")
                    && (line.contains("->DOZE") || line.contains("->OFF")));
            if screen_off_transition {
                if !(tap_clock_active && line.contains("->DOZE")) {
                    tap_clock_active = false;
                    let master = is_aod_master_enabled();
                    let content = if nothing_mode() {
                        master
                    } else {
                        settings_get("Setting_AodSwitchEnable")
                            .map(|value| value == "1").unwrap_or(master)
                    };
                    fp_only_phase = power_state::hint_only_mode(master, content);
                }
                fp_panel_allowed = true;
            }

            if pms_sleep {
                // AOSP has no "->DOZE" line: hold the AOD panel level after sleep, or
                // drop to 0 in SOFOD-only mode. write_backlight re-checks power state.
                if fp_only_phase {
                    thread::spawn(|| {
                        thread::sleep(Duration::from_millis(400));
                        write_backlight(0);
                    });
                } else {
                    let ticket = PANEL_WRITES.current();
                    thread::spawn(move || {
                        thread::sleep(Duration::from_millis(300));
                        ensure_aod_backlight(ticket);
                    });
                }
            }

            // No settings subprocesses on the pickup callback. The mode was
            // synchronized at screen-off, and write_backlight performs the
            // single fresh power-state check before changing the panel.
            if hint_wake {
                fp_panel_allowed = true;
                write_backlight(fp_bl());
                klog("Native screen-off wake -> hint brightness requested");
                if nothing_mode() && fp_only_phase {
                    // No OnScreenFingerprintIcon INVISIBLE line on AOSP: drop the hint
                    // light by timer (skipped by write_backlight if the screen turned on).
                    thread::spawn(|| {
                        thread::sleep(Duration::from_secs(6));
                        write_backlight(0);
                    });
                }
            }

            if line.contains("OnScreenFingerprintIcon") {
                if line.contains("setVisibility VISIBLE") {
                    fp_panel_allowed = true;
                    write_backlight(fp_bl());
                } else if line.contains("setVisibility INVISIBLE") && fp_panel_allowed {
                    write_backlight(if fp_only_phase { 0 } else { aod_bl() });
                }
            }

            // 6. SCREEN WAKE TO ON (Device awake / interactive)
            if line.contains("setScreenState changed:")
                && line.contains("->ON")
            {
                fp_panel_allowed = false;
                klog("SCREEN ON -> release FP brightness control");

                pending_energy_hide = false;
                let was_energy_hidden = energy_hide_active;
                energy_hide_active = false;

                if was_energy_hidden {
                    fp_only_phase = false;

                    // Restore AOD switch for next sleep cycle in background only if
                    // daemon temporarily hid it for power-saving timeout
                    thread::spawn(|| {
                        thread::sleep(Duration::from_millis(500));
                        if display_really_awake() {
                            settings_put_sync("Setting_AodSwitchEnable", "1");
                            klog("real wake -> AOD content restored (Setting_AodSwitchEnable=1)");
                        }
                    });
                } else {
                    let aod_on = is_aod_master_enabled();
                    fp_only_phase = !aod_on;
                }
            }
        }

        klog("logcat stream ended, restarting in 500ms");
        thread::sleep(Duration::from_millis(500));
    }
}
