# Building

## Toolchain

Tested environment:

- Android NDK r30
- Android API 35
- Rust with `aarch64-linux-android`
- CMake + Ninja
- ADB
- OpenSSL with Ed25519 `pkeyutl -rawin`

## FOD shim

```bash
cd ~/android/duchamp-oplus-fp-compat
cmake --build native/build -j"$(nproc)"
file native/build/libduchamp_fp_compat.so
sha256sum native/build/libduchamp_fp_compat.so
```

Expected: ARM aarch64 shared object for Android 35.

## AOD daemon

Do not deploy a host x86_64 WSL build.

```bash
cd ~/Downloads/itachi-duchamp-aodd

NDK="$HOME/Android/Sdk/ndk/30.0.16248370"
LINKER="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android35-clang"

export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$LINKER"
export CC_aarch64_linux_android="$LINKER"

cargo build --release --target aarch64-linux-android

file target/aarch64-linux-android/release/itachi-duchamp-aodd
sha256sum target/aarch64-linux-android/release/itachi-duchamp-aodd
```

Expected: ARM aarch64 PIE using `/system/bin/linker64`.

## Signing order

```text
finalize source
-> build AOD + FOD
-> calculate hashes
-> construct ITACHI4 manifest
-> sign manifest
-> update ro.itachi.aod.auth
-> install matched pair
-> verify before reboot
```

Any binary change invalidates the old signature.
