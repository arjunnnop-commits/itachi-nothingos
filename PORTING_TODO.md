# Duchamp port: still TODO (needs data from the device)

Names were converted (rodin->duchamp, neess->itachi). Values below are STILL rodin's:

1. DONE: sensor HAL name set to `sensors.mt6897.so` everywhere. Still confirm on device with
   `ls /vendor/lib64/hw | grep sensors`. Note: the sensor README still contains the old rodin SHA-256, ignore it until rebuilt.
2. Xiaomi sensor types/handles in sensor/src/sensors_duchamp_oplus_compat.c
   (33171036/33171030/33171029/33171120/33171111, handle 0x5e) -> from `dumpsys sensorservice`.
3. `k_cali` light-sensor table (rodin panel) -> bypass or re-measure.
4. Backlight sysfs node + AOD_BL=28 / FP_BL=100 in aod/src/main.rs.
5. FOD sysfs nodes in fod/native/duchamp_fp_compat.cpp (~lines 550-555, 723-743).
6. Prebuilt rodin binaries were REMOVED. Rebuild: scripts/build_aod.sh, build_fod.sh,
   sensor/build.sh, overlay/DuchampAodDozeOverlay/build.sh.
7. New signing keypair (signing/DEVELOPER-SIGNING.md), then scripts/sign_itachi4.sh.
8. Companion repo link in README still points to the original author's repo (URL kept on purpose).

## Update after duchamp_info.txt (see DEVICE_DATA.md)
- DONE: ALS raw handle fallback 0x6c; sensor types already identical to rodin.
- DONE: bake_into_rom.sh no longer writes through the sensors.mt6897.so symlink (would have overwritten the real HAL).
- OPEN: backlight node (rodin path missing) -> need values of brightness_clone / doze_brightness; AOD_BL/FP_BL unknown.
- OPEN: k_cali + ALS synthesis: duchamp has a native front light sensor (tcs3701_als) -> plan to disable synthetic ALS.
- OPEN: ROM is Transsion-based, not ColorOS: Oplus-specific parts (oplus-services.jar patchers, OplusFeatureAOD smali,
  IDisplayPanelFeature shim) may not apply. Confirm target ROM.

## Done in this round (ColorOS target on duchamp)
- aod daemon: backlight path/levels now runtime-resolved (backlight -> brightness_clone) and the startup wait is bounded.
  Override on device: `setprop persist.itachi.bl_path <node>`, `persist.itachi.aod_bl <n>`, `persist.itachi.fp_bl <n>`.
  STILL UNVERIFIED: brightness_clone semantics/scale, AOD_BL=28 / FP_BL=100. Test before trusting.
- sensor wrapper: synthetic ALS/k_cali disabled by default (DUCHAMP_NATIVE_ALS=1); pickup->tilt bridge kept.
- init rc: removed rodin /dev/disp_feature symlink, focaltech/touch_dev nodes; kept goodix_ts.0/fod_enable.
- Rust (cargo) and NDK builds were NOT run here; syntax-checked C only.

## Round 3 (everything-adapted pass)
- sepolicy: CIL append used `_202404` names (rodin vendor). bake_into_rom.sh now detects the vendor sepolicy suffix from
  plat_pub_versioned.cil and rewrites the append; it aborts if it cannot (duchamp's vendor is Android 14 based).
- INSTALLATION.md: prop block replaced with duchamp's real props; removed rodin-only props; rc snippet matches the new rc.
- Verified against the dump: FOD key 0x152 and tap scancode 354 exist on goodix_ts (event5); nonui sensor 33171027 exists;
  touch_dev/gesture_single_tap_state exists. These rodin assumptions DO hold on duchamp.
- Added framework/FOD-BRIDGE.md + ItachiFodBridge.smali (your working bridge, renamed).
- Added .github/workflows/build.yml: builds itachi_aodd, libduchamp_fp_compat.so, duchamp_fod_icon_prepare,
  sensors.mt6897.so and the Doze overlay on GitHub (no PC needed). Prebuilt rodin binaries are gone on purpose.
- STILL UNVERIFIED (needs your device/ROM): DT2W touch mode 14; brightness_clone scale; AOD_BL/FP_BL; ColorOS jar patch patterns;
  companion display/auto-brightness repo is rodin-calibrated (display config for duchamp lives in /vendor/etc/displayconfig).

## Round 4
- DuchampAodDozeOverlay.apk restored from the original (generic overlay). build_fod.sh uses install -D. Added tools/push_to_github.sh. Workflow also emits scripts/system/bin/itachi_aodd.
