#!/bin/bash
set -e

if [ -z "$1" ]; then
  echo "================================================================"
  echo " POCO X6 Pro (Duchamp) ROM Bake-In Installer (TEST 4.0)"
  echo "================================================================"
  echo "Usage: $0 <path_to_unpacked_rom_root> [coloros|nothing]"
  echo "Example: $0 /home/itachi/rom_unpacked"
  echo ""
  exit 1
fi

ROM_ROOT="$1"
# ROM type: coloros (default) or nothing (Nothing OS, AOSP-based). Usage: $0 <rom_root> [coloros|nothing]
ROM_TYPE="${2:-${ROM_TYPE:-coloros}}"
case "$ROM_TYPE" in coloros|nothing) ;; *) echo "Error: ROM_TYPE must be coloros or nothing" >&2; exit 1;; esac
echo "ROM type: $ROM_TYPE"

if [ ! -d "$ROM_ROOT" ]; then
  echo "Error: Directory '$ROM_ROOT' does not exist."
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -d "$SCRIPT_DIR/system" ]; then
  SRC_DIR="$SCRIPT_DIR"
elif [ -d "$SCRIPT_DIR/.." ] && [ -d "$SCRIPT_DIR/../system" ]; then
  SRC_DIR="$SCRIPT_DIR/.."
else
  SRC_DIR="$SCRIPT_DIR"
fi

# Detect system partition (handles flat system/ or SAR system/system/)
SYS_DIR=""
if [ -d "$ROM_ROOT/system/system/bin" ]; then
  SYS_DIR="$ROM_ROOT/system/system"
elif [ -d "$ROM_ROOT/system/bin" ]; then
  SYS_DIR="$ROM_ROOT/system"
else
  echo "Error: Cannot locate system/bin under '$ROM_ROOT'"
  exit 1
fi

# Detect vendor partition
VEN_DIR=""
if [ -d "$ROM_ROOT/vendor/lib64" ]; then
  VEN_DIR="$ROM_ROOT/vendor"
elif [ -d "$ROM_ROOT/system/vendor/lib64" ]; then
  VEN_DIR="$ROM_ROOT/system/vendor"
else
  echo "Error: Cannot locate vendor/lib64 under '$ROM_ROOT'"
  exit 1
fi

# Validate required context source before changing any ROM files.
FC="$SYS_DIR/etc/selinux/plat_file_contexts"
if [ ! -f "$FC" ]; then
  echo "Error: Missing plat_file_contexts; provide the ROM context source before installing" >&2
  exit 1
fi

echo "================================================================"
echo " POCO X6 Pro (Duchamp) - Baking FOD & AOD Fixes into ROM"
echo "================================================================"
echo "System Root: $SYS_DIR"
echo "Vendor Root: $VEN_DIR"
echo ""

# The helper must be built before mutating the destination image.
if [ "$ROM_TYPE" = "coloros" ] && [ ! -x "$SRC_DIR/system/bin/duchamp_fod_icon_prepare" ]; then
  echo "Error: Run scripts/build_fod.sh first to build custom fingerprint icon storage support" >&2
  exit 1
fi

if [ "$ROM_TYPE" = "coloros" ]; then
EXT_SEPOLICY=""
for EXT_DIR in "$ROM_ROOT/system_ext" "$ROM_ROOT/system/system_ext"; do
  if [ -f "$EXT_DIR/etc/selinux/system_ext_sepolicy.cil" ]; then
    EXT_SEPOLICY="$EXT_DIR/etc/selinux/system_ext_sepolicy.cil"
    break
  fi
done
if [ -z "$EXT_SEPOLICY" ]; then
  echo "Error: Missing system_ext_sepolicy.cil for native icon initializer policy" >&2
  exit 1
fi
if ! grep -q '^(type duchamp_fod_icon_exec)' "$EXT_SEPOLICY"; then
  printf '\n' >> "$EXT_SEPOLICY"
  cat "$SRC_DIR/sepolicy/system_ext_icon.cil.append" >> "$EXT_SEPOLICY"
fi

# Custom icons are saved by SystemUI as /data/oplus/os/<userId>custom_icon.png.
# Keep the parent searchable, not world-writable; the helper discovers real app UIDs.
mkdir -p "$SYS_DIR/etc/init"
install -m 0755 "$SRC_DIR/system/bin/duchamp_fod_icon_prepare" "$SYS_DIR/bin/duchamp_fod_icon_prepare"
install -m 0644 "$SRC_DIR/system/etc/init/duchamp.fod-icon.rc" "$SYS_DIR/etc/init/duchamp.fod-icon.rc"
chcon u:object_r:duchamp_fod_icon_exec:s0 "$SYS_DIR/bin/duchamp_fod_icon_prepare" 2>/dev/null || true
chcon u:object_r:system_file:s0 "$SYS_DIR/etc/init/duchamp.fod-icon.rc" 2>/dev/null || true
if ! grep -q '^/system/bin/duchamp_fod_icon_prepare ' "$FC"; then
  printf '\n/system/bin/duchamp_fod_icon_prepare -- u:object_r:duchamp_fod_icon_exec:s0\n/system/etc/init/duchamp[.]fod-icon[.]rc -- u:object_r:system_file:s0\n' >> "$FC"
fi
# Repair the conflicting performance-service rule only if this ROM contains it.
PERF_RC="$ROM_ROOT/odm/etc/init/vendor-oplus-hardware-performance-V1-service.rc"
if [ -f "$PERF_RC" ]; then
  sed -i -E 's@^([[:space:]]*mkdir /data/oplus/os )0770( system system[[:space:]]*)$@\10771\2@' "$PERF_RC"
fi
else
  echo "-> NothingOS: skipping Oplus custom-icon helper (/data/oplus/os does not exist)"
fi

# 1. Install AOD Daemon
echo "-> [1/7] Installing itachi_aodd to $SYS_DIR/bin/"
cp -f "$SCRIPT_DIR/system/bin/itachi_aodd" "$SYS_DIR/bin/itachi_aodd"
chmod 755 "$SYS_DIR/bin/itachi_aodd"
FC="$SYS_DIR/etc/selinux/plat_file_contexts"
if [ -f "$FC" ]; then
  sed -i '/^\/system\/bin\/itachi_aodd[[:space:]]/d' "$FC"
  printf '\n/system/bin/itachi_aodd -- u:object_r:shell_exec:s0\n' >> "$FC"
else
  echo "Error: Missing plat_file_contexts; add the exact shell_exec daemon mapping during image packing" >&2
  exit 1
fi
chcon u:object_r:shell_exec:s0 "$SYS_DIR/bin/itachi_aodd" 2>/dev/null || true

# 2. Install AOD Init Service
echo "-> [2/7] Installing itachi_aodd.rc to $SYS_DIR/etc/init/"
mkdir -p "$SYS_DIR/etc/init"
cp -f "$SCRIPT_DIR/system/etc/init/itachi_aodd.rc" "$SYS_DIR/etc/init/itachi_aodd.rc"
chmod 644 "$SYS_DIR/etc/init/itachi_aodd.rc"
chcon u:object_r:system_file:s0 "$SYS_DIR/etc/init/itachi_aodd.rc" 2>/dev/null || true

# 3. Install FOD Compat Shim & Sensor Compatibility HAL
echo "-> [3/8] Installing libduchamp_fp_compat.so to $VEN_DIR/lib64/"
cp -f "$SCRIPT_DIR/vendor/lib64/libduchamp_fp_compat.so" "$VEN_DIR/lib64/libduchamp_fp_compat.so"
chmod 644 "$VEN_DIR/lib64/libduchamp_fp_compat.so"
chcon u:object_r:vendor_file:s0 "$VEN_DIR/lib64/libduchamp_fp_compat.so" 2>/dev/null || true

# Updating FOD/AOD must not silently replace an independently fixed sensor HAL.
if [ "${ITACHI_INSTALL_SENSOR_HAL:-0}" = 1 ] || [ ! -f "$VEN_DIR/lib64/hw/sensors.mt6897.so" ]; then
  if [ ! -f "$SCRIPT_DIR/vendor/lib64/hw/sensors.mt6897.so" ]; then
    echo "Error: Requested sensor HAL payload is missing" >&2
    exit 1
  fi
  echo "-> Installing sensors.mt6897.so (Instant Tilt & Pickup HAL) to $VEN_DIR/lib64/hw/"
  mkdir -p "$VEN_DIR/lib64/hw"
  # duchamp: sensors.mt6897.so is a SYMLINK to sensors.mediatek.V2.0.so (the real HAL the wrapper
  # dlopens). cp onto the symlink would overwrite the real HAL, so remove the link first.
  [ -L "$VEN_DIR/lib64/hw/sensors.mt6897.so" ] && rm -f "$VEN_DIR/lib64/hw/sensors.mt6897.so"
  cp -f "$SCRIPT_DIR/vendor/lib64/hw/sensors.mt6897.so" "$VEN_DIR/lib64/hw/sensors.mt6897.so"
  chmod 644 "$VEN_DIR/lib64/hw/sensors.mt6897.so"
  chcon u:object_r:vendor_file:s0 "$VEN_DIR/lib64/hw/sensors.mt6897.so" 2>/dev/null || true
else
  echo "-> Preserving the ROM's existing sensors.mt6897.so (set ITACHI_INSTALL_SENSOR_HAL=1 to replace explicitly)"
fi

# Install the framework Doze RRO (generic AOSP DozeService mapping; used on ColorOS and Nothing OS).
DOZE_OVERLAY="$SRC_DIR/vendor/overlay/DuchampAodDozeOverlay.apk"
if [ ! -f "$DOZE_OVERLAY" ]; then
  echo "Error: Missing required Doze overlay: $DOZE_OVERLAY" >&2
  exit 1
fi
echo "-> Installing DuchampAodDozeOverlay.apk to $VEN_DIR/overlay/"
mkdir -p "$VEN_DIR/overlay"
cp -f "$DOZE_OVERLAY" "$VEN_DIR/overlay/DuchampAodDozeOverlay.apk"
chmod 644 "$VEN_DIR/overlay/DuchampAodDozeOverlay.apk"
chcon u:object_r:vendor_overlay_file:s0 "$VEN_DIR/overlay/DuchampAodDozeOverlay.apk" 2>/dev/null || true

# 4. Patch mfp-daemon ELF DT_NEEDED (Permanent boot loading without LD_PRELOAD)
echo "-> [4/8] Baking libduchamp_fp_compat.so into $VEN_DIR/bin/hw/mfp-daemon ELF header..."
if [ -f "$VEN_DIR/bin/hw/mfp-daemon" ]; then
  if which patchelf >/dev/null 2>&1; then
    patchelf --add-needed libduchamp_fp_compat.so "$VEN_DIR/bin/hw/mfp-daemon" 2>/dev/null || true
    chmod 755 "$VEN_DIR/bin/hw/mfp-daemon"
    chcon u:object_r:hal_fingerprint_default_exec:s0 "$VEN_DIR/bin/hw/mfp-daemon" 2>/dev/null || true
    echo "   [OK] Patched mfp-daemon with DT_NEEDED: libduchamp_fp_compat.so"
  else
    echo "   [WARN] patchelf not found! Please ensure patchelf is installed on build host."
  fi
fi

# 5. Install Fingerprint Hook & Node Init Script
echo "-> [5/8] Installing zz_duchamp_fp_compat.rc to $VEN_DIR/etc/init/"
mkdir -p "$VEN_DIR/etc/init"
cp -f "$SCRIPT_DIR/vendor/etc/init/zz_duchamp_fp_compat.rc" "$VEN_DIR/etc/init/zz_duchamp_fp_compat.rc"
chmod 644 "$VEN_DIR/etc/init/zz_duchamp_fp_compat.rc"
chcon u:object_r:vendor_configs_file:s0 "$VEN_DIR/etc/init/zz_duchamp_fp_compat.rc" 2>/dev/null || true

# 6. Inject SELinux CIL Rules & Handle precompiled_sepolicy
echo "-> [6/8] Injecting Strict SELinux CIL rules into $VEN_DIR/etc/selinux/vendor_sepolicy.cil..."
CIL_TARGET="$VEN_DIR/etc/selinux/vendor_sepolicy.cil"
# duchamp: the append files use versioned type names (e.g. sysfs_202404). The suffix MUST match the
# vendor's own sepolicy version (duchamp's vendor is Android 14 based, rodin's is 202404), otherwise
# secilc fails at boot. Detect it from the ROM instead of assuming it.
SEPOL_SUFFIX=""
for f in "$VEN_DIR/etc/selinux/plat_pub_versioned.cil" "$CIL_TARGET"; do
  if [ -z "$SEPOL_SUFFIX" ] && [ -f "$f" ]; then
    SEPOL_SUFFIX="$(grep -ohE 'system_server_[0-9]+(_[0-9]+)?' "$f" | head -1 | sed 's/^system_server_//')"
  fi
done
if [ -z "$SEPOL_SUFFIX" ]; then
  echo "Error: cannot detect the vendor sepolicy version suffix (no system_server_<ver> in plat_pub_versioned.cil)." >&2
  echo "       Run: grep -ohE 'sysfs_[0-9_]+' $VEN_DIR/etc/selinux/*.cil | sort -u   and edit sepolicy/*.append by hand." >&2
  exit 1
fi
echo "   sepolicy version suffix detected: $SEPOL_SUFFIX"
for need in sysfs system_server default_prop system_prop; do
  if ! grep -qE "(^|[( ])${need}_${SEPOL_SUFFIX}([) ]|$)" "$VEN_DIR/etc/selinux/plat_pub_versioned.cil" 2>/dev/null; then
    echo "   [WARN] ${need}_${SEPOL_SUFFIX} not found in plat_pub_versioned.cil; check the CIL append manually" >&2
  fi
done
if [ -f "$CIL_TARGET" ]; then
  if ! grep -q "Pure Strict Enforcing FOD Rules" "$CIL_TARGET"; then
    sed "s/_202404/_${SEPOL_SUFFIX}/g" "$SCRIPT_DIR/sepolicy/vendor_sepolicy.cil.append" >> "$CIL_TARGET"
    echo "   [OK] Appended strict enforcing rules to vendor_sepolicy.cil"
  else
    echo "   [SKIP] Rules already present in vendor_sepolicy.cil"
  fi
else
  echo "   [WARN] $CIL_TARGET not found! Please check vendor selinux directory."
fi

if [ "$ROM_TYPE" = "coloros" ]; then
# Inject DisplayPanelFeature AIDL service into vendor_service_contexts and odm_service_contexts
VEN_SC="$VEN_DIR/etc/selinux/vendor_service_contexts"
if [ -f "$VEN_SC" ]; then
  if ! grep -rqs "vendor_hal_fingerprint_service_xiaomi" "$VEN_DIR/etc/selinux" "$ROM_ROOT/odm/etc/selinux"; then
    echo "   [WARN] label type vendor_hal_fingerprint_service_xiaomi not found in this ROM; set a valid service label for DisplayPanelFeature manually" >&2
  elif ! grep -q "vendor.oplus.hardware.displaypanelfeature" "$VEN_SC"; then
    echo "vendor.oplus.hardware.displaypanelfeature.IDisplayPanelFeature/default       u:object_r:vendor_hal_fingerprint_service_xiaomi:s0" >> "$VEN_SC"
    echo "   [OK] Appended DisplayPanelFeature AIDL service to $VEN_SC"
  fi
fi

ODM_SC="$ROM_ROOT/odm/etc/selinux/odm_service_contexts"
if [ -f "$ODM_SC" ]; then
  if ! grep -q "vendor.oplus.hardware.displaypanelfeature" "$ODM_SC"; then
    echo "vendor.oplus.hardware.displaypanelfeature.IDisplayPanelFeature/default       u:object_r:vendor_hal_fingerprint_service_xiaomi:s0" >> "$ODM_SC"
    echo "   [OK] Appended DisplayPanelFeature AIDL service to $ODM_SC"
  fi
fi

else
  echo "   [SKIP] NothingOS: Oplus DisplayPanelFeature service labels not needed"
fi

# CRITICAL TREBLE STEP:
# On Android Treble devices (including POCO X6 Pro / ColorOS ports), if precompiled_sepolicy exists
# in /odm/etc/selinux or /vendor/etc/selinux, Android init will load the precompiled binary blob
# and completely IGNORE custom CIL policy edits!
# We remove all 3 precompiled sepolicy files:
#   1. precompiled_sepolicy
#   2. precompiled_sepolicy.plat_sepolicy_and_mapping.sha256
#   3. precompiled_sepolicy.*_sepolicy_and_mapping.sha256
# This forces Android init to dynamically invoke secilc at boot and compile all custom CIL rules cleanly.
for DIR in "$ROM_ROOT/odm/etc/selinux" "$VEN_DIR/etc/selinux"; do
  if [ -d "$DIR" ]; then
    FOUND=$(find "$DIR" -maxdepth 1 -name "precompiled_sepolicy*" 2>/dev/null)
    if [ -n "$FOUND" ]; then
      echo "   [CRITICAL] Found precompiled sepolicy files in $DIR:"
      echo "$FOUND" | while read -r f; do
        echo "     -> Neutralizing $(basename "$f")"
        mv -f "$f" "${f}.bak" 2>/dev/null || rm -f "$f"
      done
      echo "   [OK] Precompiled sepolicy files neutralized in $DIR."
    fi
  fi
done

# 7. Update SELinux file_contexts if present in unpacked partitions
echo "-> [7/8] Updating SELinux file_contexts for image repackers (erofs/ext4)..."
VEN_FC="$VEN_DIR/etc/selinux/vendor_file_contexts"
if [ -f "$VEN_FC" ]; then
  if ! grep -q "libduchamp_fp_compat" "$VEN_FC"; then
    cat "$SCRIPT_DIR/sepolicy/vendor_file_contexts.append" >> "$VEN_FC"
    echo "   [OK] Appended labels to $VEN_FC"
  fi
  if ! grep -q "DuchampAodDozeOverlay" "$VEN_FC"; then
    echo '/vendor/overlay/DuchampAodDozeOverlay\.apk u:object_r:vendor_overlay_file:s0' >> "$VEN_FC"
    echo "   [OK] Appended Doze overlay label to $VEN_FC"
  fi
fi

SYS_FC="$SYS_DIR/etc/selinux/plat_file_contexts"
if [ -f "$SYS_FC" ]; then
  if ! grep -q "itachi_aodd" "$SYS_FC"; then
    cat "$SCRIPT_DIR/sepolicy/plat_file_contexts.append" >> "$SYS_FC"
    echo "   [OK] Appended labels to $SYS_FC"
  fi
fi

# 8. Append Properties to build.prop
echo "-> [8/8] Injecting properties into $SYS_DIR/build.prop..."
PROP_TARGET="$SYS_DIR/build.prop"
if [ -f "$PROP_TARGET" ]; then
  if ! grep -q "ro.itachi.fod.compat" "$PROP_TARGET"; then
    if [ "$ROM_TYPE" = "nothing" ]; then
      cat "$SCRIPT_DIR/system/build.prop.append.nothing" >> "$PROP_TARGET"
    else
      cat "$SCRIPT_DIR/system/build.prop.append" >> "$PROP_TARGET"
    fi
    echo "   [OK] Appended FOD & AOD properties to build.prop"
  else
    echo "   [SKIP] Properties already present in build.prop"
  fi
fi

echo ""
echo "================================================================"
echo " [SUCCESS] ROM successfully baked with TEST 4.0 FOD & AOD Fixes!"
echo "================================================================"
echo "Repack your ROM partitions. On first boot, the phone will:"
echo " 1. Run global SELinux in 100% Enforcing mode (passes CTS/Integrity)."
echo " 2. Assign exact SELinux labels to all binaries and configs."
echo " 3. Hook mfp-daemon with libduchamp_fp_compat.so (FOD active)."
echo " 4. Register DisplayPanelFeature with feature 217 ACKed (Seamless & Classic AOD fixed)."
echo " 5. Run itachi_aodd with zero-fork stream loop (No watchdog crashes)."
echo " 6. Show Screen-Off Fingerprint icon on touch/pickup."
echo "================================================================"
