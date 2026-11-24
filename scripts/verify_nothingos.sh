#!/system/bin/sh
# Run as root on the phone after first NothingOS boot.
echo "== props =="; getprop ro.itachi.rom; getprop init.svc.itachi_aodd; getprop persist.vendor.sys.fp.vendor
echo "== daemon =="; /system/bin/itachi_aodd --verify-only; echo "exit=$?"
echo "== shim loaded in mfp-daemon =="; grep -l libduchamp_fp_compat /proc/$(pidof mfp-daemon | awk '{print $1}')/maps 2>/dev/null
logcat -d -s DuchampFpCompat 2>/dev/null | grep -i "nothingos" | tail -5
echo "== oplus panel service must be ABSENT on nothing =="; service list | grep -i displaypanelfeature || echo "absent (ok)"
echo "== AOD setting =="; settings get secure doze_always_on
echo "== logcat patterns itachi_aodd relies on (count in last dump) =="
for p in "setScreenState changed" "Final-state=DOZE_SUSPEND" "performAodUpdate" "WorkshopAodController" "OnScreenFingerprintIcon" "notifyWakeUpCallback" "DuchampSensorCompat"; do
  printf "%-28s %s\n" "$p" "$(logcat -d -b all | grep -c "$p")"
done
echo "== AOSP doze/udfps candidates =="
logcat -d -b all | grep -iE "DozeMachine|UdfpsController|Display power state|DozeScreenState" | tail -15
