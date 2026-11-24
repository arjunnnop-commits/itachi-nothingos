# Duchamp (POCO X6 Pro / 2311DRK48I) data from duchamp_info.txt

- SoC mt6897. Build seen: CL9-16.3.0.155SP09, Android 16, fingerprint Transsion/tssi (HiOS-style), NOT ColorOS.
  No oplus-services.jar, no Oplus services; system_server logs TranFingerprintAppComponentImpl.
- /vendor/lib64/hw/sensors.mt6897.so -> symlink to sensors.mediatek.V2.0.so (sha256 33744b46...c6682).
- Sensors (same Xiaomi types as rodin; handles differ): pickup 33171036 h=0x19, fod 33171030 h=0x52,
  aod 33171029 h=0x53, imu_hand 33171120 h=0x6b, als_raw 33171111 h=0x6c, tilt(22) h=0x16 (native MTK, wakeup),
  light tcs3701_als type 5 h=0x5 (native).
- Touch IC: goodix_ts (/sys/devices/platform/goodix_ts.0/{fod_enable,aod_enable}); /sys/class/touch/touch_dev/fod_press_status
  exists; touch_dev/fod_enable does NOT exist. Input: event5 goodix_ts, event2 uinput-xiaomi.
- FOD sensor: goodix_fod (module ofilm), optical; location 504,2332 size 210x210. /odm/lib64/hw has fingerprint.goodix_fod.so + fingerprint.fpc_fod.so.
- Services present: IXiaomiFingerprint, ITouchFeature, IFingerprint(AIDL). Not present: Oplus IDisplayPanelFeature.
- Panel: dsi_n11a_42_02_0a_dsc_vdo, 1220x2712. /sys/class/mi_display/disp-DSI-0/ has NO `backlight`; has brightness_clone, doze_brightness, disp_param.
  No /sys/class/backlight. -> rodin backlight path in aod daemon/sensor wrapper does not exist on duchamp.
- SELinux Enforcing, root via KernelSU (u:r:ksu:s0).
