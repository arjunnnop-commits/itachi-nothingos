# Installation & SELinux File Contexts Guide

## Installed Paths, Permissions & SELinux Labels

When installing manually or integrating into an unpacked ROM, every file must have the correct ownership, permissions, and SELinux context (`chcon`):

| File Path in ROM | Permissions | Owner | SELinux Context | Description |
|---|---|---|---|---|
| `/system/bin/itachi_aodd` | `0755` (`rwxr-xr-x`) | `root:root` | `u:object_r:shell_exec:s0` | Native AOD backlight & SOFOD daemon executable |
| `/system/etc/init/itachi_aodd.rc` | `0644` (`rw-r--r--`) | `root:root` | `u:object_r:system_file:s0` | Daemon init service definition (`seclabel u:r:shell:s0`) |
| `/vendor/lib64/libduchamp_fp_compat.so` | `0644` (`rw-r--r--`) | `root:root` | `u:object_r:vendor_file:s0` | Fingerprint & panel feature 217 compat shim |
| `/vendor/etc/init/zz_duchamp_fp_compat.rc` | `0644` (`rw-r--r--`) | `root:root` | `u:object_r:vendor_configs_file:s0` | Hardware hook & Goodix touch (goodix_ts) permissions |
| `/vendor/etc/selinux/vendor_sepolicy.cil` | `0644` (`rw-r--r--`) | `root:root` | `u:object_r:vendor_sepolicy_file:s0` | Treble vendor CIL policy (with per-domain permissive) |

---

## File Contexts for Image Repackers (`erofs` / `ext4` / `e2fsdroid`)

If you are packing partition images using `mkfs.erofs` or `e2fsdroid`, add these entries to your partition's `file_contexts`:

### 1. `plat_file_contexts` (System Partition)
```text
/system/bin/itachi_aodd                   u:object_r:shell_exec:s0
/system/etc/init/itachi_aodd\.rc          u:object_r:system_file:s0
```

### 2. `vendor_file_contexts` (Vendor Partition)
```text
/vendor/lib64/libduchamp_fp_compat\.so    u:object_r:vendor_file:s0
/vendor/etc/init/zz_duchamp_fp_compat\.rc u:object_r:vendor_configs_file:s0
```

---

## Init Services

### AOD Daemon (`system/etc/init/itachi_aodd.rc`)
```rc
service itachi_aodd /system/bin/itachi_aodd
    class late_start
    user root
    group root system log
    seclabel u:r:shell:s0
```

### FOD hook / node permissions (`vendor/etc/init/zz_duchamp_fp_compat.rc`)
`bake_into_rom.sh` adds `librodin`-style DT_NEEDED (now `libduchamp_fp_compat.so`) to `mfp-daemon` with patchelf, so no LD_PRELOAD service override is needed on duchamp.
```rc
# duchamp (POCO X6 Pro, mt6897): the kernel already exposes /dev/mi_display/disp_feature
# (root:graphics 0666), so the rodin /dev/disp_feature symlink block was removed.

on boot
    # Goodix touchscreen FOD node (duchamp touch IC = goodix_ts)
    chown system system /sys/devices/platform/goodix_ts.0/fod_enable
    chmod 0660 /sys/devices/platform/goodix_ts.0/fod_enable

    # AOD doze brightness / brightness clone (used by itachi_aodd)
    chown system system /sys/devices/virtual/mi_display/disp_feature/disp-DSI-0/doze_brightness
    chown system system /sys/devices/virtual/mi_display/disp_feature/disp-DSI-0/brightness_clone

    # Xiaomi FOD engine: turn off LHBM immediately upon auth result
    setprop persist.vendor.sys.fp.fod.lhbmoffafterresult 1
```

---

## Build Properties

### System Properties (`system/build.prop`)

```properties
sys.itachi4.authorized=1
ro.itachi.fod.compat=1
persist.sys.duchamp.aod_keep_doze=1
ro.oplus.aod.fod.support=true
```

### Vendor Properties (Append to `vendor.prop` or `vendor/build.prop`)

```properties
# AIDL Fingerprint HAL
vendor.fingerprint.aidl.support=1

# ColorOS FOD UI gate (duchamp: optical Goodix, 210x210 sensor, top-left 504,2332)
persist.vendor.fingerprint.type=udfps_optical
persist.vendor.fingerprint.sensor_type=optical
persist.vendor.fingerprint.fod.enable=true
persist.vendor.fingerprint.animation=true
persist.vendor.fingerprint.sensor_location=504,2332,105
persist.vendor.fp.vendor=goodix

# Oplus optical fingerprint support
ro.oplus.biometrics.fingerprint.optical=true
ro.oplus.aod.support=true
ro.oplus.aod.fod.support=true
ro.vendor.fod.animation.support=true
persist.sys.fingerprint.animation=1
persist.sys.fp.fod.anim=1
persist.sys.fp.fod.screenoff=true

# Duchamp stock Xiaomi FOD/display props (read from a working duchamp, 2311DRK48I)
ro.hardware.fp.fod=true
ro.hardware.fp.fod.location=low
ro.hardware.fp.fod.touch.ctl.version=2.0
ro.hardware.fp.mievent=true
ro.vendor.localhbm.enable=true
ro.vendor.mtk_aod_support=1
ro.vendor.display.fod_monitor_default_fps=120
ro.vendor.display.aod_monitor_default_fps=30

# Duchamp Goodix FOD values
persist.vendor.sys.fp.vendor=goodix_fod
persist.vendor.sys.fp.module=ofilm
persist.vendor.sys.fp.expolevel=0x88
persist.vendor.sys.fp.fod.location.X_Y=504,2332
persist.vendor.sys.fp.fod.size.width_height=210,210
persist.vendor.sys.fp.fp_anti_mistouch=true
persist.vendor.sys.fp.heartbeat=true
# NOTE: persist.vendor.sys.fp.info / .uid are per-unit values written by the HAL; never copy them.
# NOTE: rodin-only props (tddi, halworkmode, onetrack, fod.optimize, lowlight thresholds) are NOT set on duchamp stock and were removed.
# NOTE: X_Y is the top-left corner (center = 504+105, 2332+105 = 609,2437). If the ColorOS icon is offset,
#       sensor_location may expect the CENTER: try 609,2437,105.
```

---

## Post-Boot Verification

Run in ADB shell:
```bash
# Verify SELinux global state (Must return Enforcing)
getenforce

# Verify file labels
ls -lZ /system/bin/itachi_aodd
ls -lZ /vendor/lib64/libduchamp_fp_compat.so

# Verify services
getprop init.svc.itachi_aodd
getprop init.svc.mfp-daemon
```

## Custom fingerprint icons

Run `scripts/build_fod.sh` before baking. This builds the native, one-shot
`/system/bin/duchamp_fod_icon_prepare` and installs it with
`/system/etc/init/duchamp.fod-icon.rc`. The binary uses `duchamp_fod_icon_exec`
and mode 0755; the RC uses `system_file` and mode 0644. Both are root:root.
The bake step adds `sepolicy/system_ext_icon.cil.append` to system_ext policy:
this defines a dedicated domain and executable type. Init transitions into
`duchamp_fod_icon`; the utility runs as system with only CHOWN and FOWNER
capabilities to assign the icon files. It reads PackageManager’s UID map and
has no access to private app data. Recompile the combined ROM policy and
apply the matching file context when packing. The post-fs-data action also
restores that context before executing it.

ColorOS SystemUI saves icons directly to `/data/oplus/os/<userId>custom_icon.png`.
The user ID is a filename prefix; do not insert another slash. A port's performance
init rule can reset `/data/oplus/os` to system:system 0770, causing EACCES even
though Settings accepts the icon. The bake step changes that conflicting rule to
0771 where present. The initializer also restores 0771 and prepares each existing
user's exact icon file using the SystemUI app ID from PackageManager’s
`/data/system/packages.list`. It does not truncate images or make the
directory writable by other apps.

The initializer runs before framework startup and retries after boot completes,
so a first boot can resolve PackageManager’s newly created UID entry. After
creating a new Android user, reboot before using custom icons for that user.
The existing ColorOS `platform_app` access to `os_data_file` is required; no
permissive domain or extra SystemUI data-access grant is installed by this fix.
After installation, select the custom icon again to retry the previously failed
copy, then check it on the lock screen and after reboot. This storage fix is
independent of Goodix/Jiiov fingerprint sensors and Goodix/FocalTech touch panels.

Check the automatic boot run with `adb shell logcat -d -s DuchampFodIcon`.
The completion line must report `failures=0`; `init.svc.duchamp_fod_icon_prepare`
should be `stopped` after the one-shot completes.
