# itachi-duchamp: ColorOS FOD/AOD fixes adapted for POCO X6 Pro (duchamp, mt6897)

Ported from NEESS-COS-AOD-FOD-FIX (POCO X7 Pro / rodin, Apache-2.0, see NOTICE).
Naming: rodin -> duchamp, nees/neess/neeschal -> itachi.

IMPORTANT: these fixes patch a **ColorOS** ROM (Oplus SystemUI/framework). They do nothing on HyperOS/HiOS/AOSP.
Use them when you have a ColorOS build for duchamp.

## 1. Build the binaries (no PC needed)
1. Make an EMPTY private GitHub repo + token, then in Termux (`pkg install git`) from this folder:
   `GH_USER=you GH_REPO=name GH_TOKEN=xxxx sh tools/push_to_github.sh`  (keeps `.github/workflows/build.yml`).
2. Actions tab -> build-itachi-duchamp -> Run workflow.
3. Download artifact `itachi-duchamp-payload`; copy its `system/` and `vendor/` folders over this repo's
   `system/` and `vendor/` (same layout).

## 2. Install into a ColorOS ROM
`./bake_into_rom.sh /path/to/unpacked_rom`   (needs patchelf; it auto-detects the vendor sepolicy suffix)
Keep SELinux Enforcing. Do NOT use it on non-ColorOS ROMs.

## 3. Framework parts (need the ROM's oplus-services.jar / services.jar)
- framework/tools/patch_duchamp_{dt2w,proximity,tap_aod}.py + the .md guides
- framework/FOD-BRIDGE.md + smali/.../ItachiFodBridge.smali (your working FOD bridge)

## 4. Duchamp-specific values already set (from the real device)
sensor HAL `sensors.mt6897.so` (symlink-safe install), sensor types/handles (auto-detected), touch IC goodix_ts,
FOD Goodix/ofilm 504,2332 210x210, init rc nodes, vendor props, backlight path auto-detect.

## 5. Must be checked on the first ColorOS boot
- `persist.itachi.bl_path|aod_bl|fp_bl` (brightness_clone scale, AOD=28 / FP=100 are guesses)
- DT2W touch mode 14, jar patch patterns, FOD icon offset (try sensor_location 609,2437,105)
- `getprop init.svc.itachi_aodd`, `logcat | grep -i itachi`, `/system/bin/itachi_aodd --verify-only`
- Signing: the embedded public key is the original author's; for your own signed build use signing/DEVELOPER-SIGNING.md.

Rollback: restore the backed-up system/vendor/odm images. Always back up before flashing.
See PORTING_TODO.md and DEVICE_DATA.md for details.

## Binary status
- Included, working as-is: `vendor/overlay/DuchampAodDozeOverlay.apk` (generic Doze config; original build, internal package id unchanged).
- Built by the workflow (cannot be compiled offline): `system/bin/itachi_aodd`, `system/bin/duchamp_fod_icon_prepare`,
  `vendor/lib64/libduchamp_fp_compat.so`, `vendor/lib64/hw/sensors.mt6897.so`. The old rodin binaries were NOT kept because
  they use the old property/service names and rodin's HAL name, so they would not match the renamed rc/sepolicy/scripts.
