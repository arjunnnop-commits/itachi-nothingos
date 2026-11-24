# Itachi FOD/AOD -> NothingOS (POCO X6 Pro / duchamp)

NothingOS is AOSP-based (no Oplus framework). Is repo ka ColorOS-only hissa isliye alag kiya gaya hai.
Mode switch: `ro.itachi.rom=nothing` (bake script apne aap set karta hai).

## Install
```
./bake_into_rom.sh /path/to/unpacked_rom nothing
```
Binaries (libduchamp_fp_compat.so, itachi_aodd) ko GitHub Actions workflow se REBUILD karo, kyunki
source mein nothing-mode gate add hua hai. Purane prebuilt binaries ColorOS behaviour hi denge.

## Kya change hua (nothing mode mein)
| Part | ColorOS | NothingOS |
|---|---|---|
| Oplus IDisplayPanelFeature shim (feature 211/217/22/179) | register hota hai | **register nahi hota** (AOSP SystemUI mein dim layer/black box hi nahi hai) |
| ColorOS touch callback (tx 1001, cmd 1201/1202) | SystemUI ko bheja jata hai | **skip** (AOSP UdfpsController khud touch detect karta hai) |
| Enroll haptic (Xiaomi vibrator) | shim bajata hai | **skip** (NothingOS khud karta hai) |
| Standard AIDL session hooks (enroll/authenticate start, LHBM off after auth, Xiaomi touch arm/disarm, Jiiov idle disarm) | active | **active (same)** |
| AOD daemon AOD on/off | `Setting_AodSwitchEnable` | `Settings.Secure doze_always_on` |
| AOD daemon energy-saving/schedule | `Setting_Aod*` keys | nahi hai -> enabled = all-day |
| Setting_AodSwitchEnable writes (SOFOD trick) | haan | **band** (warna user ki AOD setting chhed jaati) |
| build.prop | `ro.oplus.*` props | sirf `ro.itachi.*` + vendor fp props (`build.prop.append.nothing`) |
| /data/oplus/os custom icon helper + CIL | install | **skip** |
| DisplayPanelFeature service_contexts | append | **skip** |
| Doze overlay (DozeService, android.sensor.light) | install | install (generic AOSP value) |
| Vendor rc (goodix fod_enable chown, brightness_clone, lhbmoff prop), sepolicy hal_fingerprint rules, sensor HAL pickup bridge | install | install (vendor-side, ROM-independent) |

## Ye NothingOS pe lagu nahi hote (use mat karo)
`framework/` poora: `OplusFeatureAOD.property-gated.smali`, `patch_duchamp_dt2w.py`,
`patch_duchamp_tap_aod.py`, `patch_duchamp_proximity.py`, `DuchampTouchBridge/AodTapBridge.java`.
Ye `oplus-services.jar` / `ColorTouchNodeManagerService` / `OplusScreenOffGesturePolicy` patch karte hain, jo NothingOS mein hain hi nahi.
NothingOS ke liye equivalent (DT2W, tap-to-wake, proximity) AOSP services.jar / Nothing ke apne classes mein alag se likhne padenge
(pehle `framework/` ke Oplus patchers ki jagah NothingOS jar ke classes dekhne honge, jo is zip se nahi dikh sakte).

## Abhi verify NAHI hua (device/ROM chahiye, yahan compile/test nahi ho sakta)
1. Rust/C++ build nahi chalaya (sandbox mein cargo/NDK nahi). Sirf source-level edit + `bash -n` check hua. Workflow se build karke dekho.
2. AOD daemon logcat strings (`setScreenState changed:`, `Final-state=DOZE_SUSPEND`, `performAodUpdate`,
   `WorkshopAodController`, `OnScreenFingerprintIcon`) ColorOS ke hain. NothingOS pe kaunse milte hain,
   `scripts/verify_nothingos.sh` chala ke dekho. Jo na mile unke liye daemon mein AOSP equivalent string lagani hogi.
3. FOD icon position/size: AOSP UDFPS sensor location HAL SensorProps se leta hai (504,2332 210x210 -> center 609,2437, r=105).
   Agar icon offset ho to wahi values check karo.
4. AOSP mein LHBM/HBM vendor `mfp-daemon` khud handle karta hai. Agar NothingOS ke SystemUI mein FOD pe lockscreen dim/black box dikhe
   to batao, wo Nothing ki apni customisation hogi.
5. Signing: `itachi_aodd` ki authorization original author ki public key se bandhi hai. Apni key ke liye `signing/DEVELOPER-SIGNING.md`.

## Update 2: AOD daemon ab AOSP events pe chalta hai (nothing mode)
- Screen-off: AOSP PowerManagerService ki `Going to sleep due to` line (ColorOS `->DOZE` ki jagah).
- AOD keepalive: 1s polling (panel 0 ho to AOD level wapas, `doze_always_on=1` hone par).
- SOFOD hint: pickup/tap pe fp brightness, 6s timer se wapas 0 (ColorOS `OnScreenFingerprintIcon` line ki jagah).
- Abhi bhi untested: build + on-device test baaki.
