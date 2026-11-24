#!/usr/bin/env bash
set -euo pipefail
adb shell 'su -M -c "
echo ===== SERVICES =====
echo AOD_state=$(getprop init.svc.itachi_aodd)
echo AOD_pid=$(pidof itachi_aodd)
echo MFP_state=$(getprop init.svc.mfp-daemon)
echo MFP_pid=$(pidof mfp-daemon)

echo
echo ===== AUTH =====
echo runtime_auth=$(getprop sys.itachi4.authorized)
/system/bin/itachi_aodd --verify-only
echo verify_rc=$?

echo
echo ===== HASHES =====
sha256sum /system/bin/itachi_aodd
sha256sum /vendor/lib64/libduchamp_fp_compat.so
sha256sum /vendor/lib64/hw/sensors.mt6897.so

echo
echo ===== PANEL SERVICE =====
service list | grep -i displaypanelfeature || true

echo
echo ===== STARTUP LOGS =====
logcat -b all -d -v time | grep -Ei \
\"V4 shared authorization OK|ITACHI4 runtime authorization published|ITACHI4 runtime authorization OK|authorization timeout|OplusPanel registered\" \
| tail -100
"'
