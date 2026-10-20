# faebix-native-libs

Prebuilt native image libraries for Android, built from public source with one
scripted build and pinned tool versions. The Android apps of faebix (VelaGallery) link these
libraries to write very large JPEG files in strips and to find the preview
image inside camera RAW files.

The repository holds only third-party C and C++ source code (unchanged), the
build scripts, the licenses and this README. App code is not part of it.

## Libraries

| Library | Version | Source | License | Built as |
|---|---|---|---|---|
| [libjpeg-turbo](https://libjpeg-turbo.org) | 3.2.0 | [release archive](https://github.com/libjpeg-turbo/libjpeg-turbo/releases/tag/3.2.0), GPG signature checked | IJG License, Modified (3-clause) BSD License, zlib License (SIMD code) | `libjpeg.a`, libjpeg API only, SIMD on |
| [piex](https://github.com/google/piex) (Preview Image Extractor) | commit [`4d59203`](https://github.com/google/piex/commit/4d59203c0aa957e9b80a7c7ca78f7af1771dc033) (2024-01-22) | git | Apache License 2.0 | `libpiex.a` |

The exact sources, checksums and the signing key fingerprint are in
[`SOURCES`](SOURCES). [`scripts/verify-sources.sh`](scripts/verify-sources.sh)
downloads the upstream sources again and compares them file by file with
`third_party/`; the CI runs it before every build.

The libjpeg-turbo source also contains libspng and zlib
(`third_party/libjpeg-turbo/src/spng`, used by its command-line tools). They
are not built into the archives and keep their own licenses there.

piex ships only a gyp file upstream. [`cmake/piex/CMakeLists.txt`](cmake/piex/CMakeLists.txt)
builds the same source files with CMake. No source file is changed.

## What gets built

For each ABI `arm64-v8a`, `armeabi-v7a`, `x86` and `x86_64`:

- static libraries `lib/libjpeg.a` and `lib/libpiex.a`, position independent,
  debug info stripped, built with the Android NDK r28 (28.2.13676358),
  minimum API 31, `c++_static`
- headers in `include/` (`jpeglib.h`, `jconfig.h`, `jmorecfg.h`, `jerror.h`,
  and `include/piex/src/...`)
- `licenses/`, `NOTICE`, `BUILDINFO` (versions, NDK, source commit) and
  `FILES.sha256` (a SHA-256 checksum for every file in the archive)

Static libraries are linked into the app's own JNI library, so the app ships
one shared library and only the code it uses. The build also links both
libraries into a small test library ([`test/linkcheck`](test/linkcheck)) whose
code writes a JPEG with an ICC profile and passes it to piex. It is only
linked, not executed: linking with `--no-undefined` catches missing symbols,
and [`scripts/check-16k.sh`](scripts/check-16k.sh) checks that every
LOAD segment of the result is aligned to 16 KB, as required for 16 KB page
devices. 16 KB pages exist only on 64-bit devices, so the check applies to
`arm64-v8a` and `x86_64`; the 32-bit ABIs keep the NDK's 4 KB alignment.

## Build

Needs bash, CMake 3.15 or newer, Ninja, GNU tar, gzip, sha256sum, git, and the
Android NDK r28 or newer. x86 and x86_64 also need NASM.
`scripts/verify-sources.sh` also needs curl and gpg.

```bash
export ANDROID_NDK_HOME=/path/to/android-ndk
scripts/build-android.sh                 # all four ABIs
scripts/build-android.sh arm64-v8a       # one ABI
```

The archives land in `dist/`, one per ABI, with `dist/SHA256SUMS`.

## Releases

[`.github/workflows/build.yml`](.github/workflows/build.yml) builds every ABI
on each push to `main` and each pull request. Started by hand on `main` with a tag such as
`v1.0.0`, it publishes a GitHub release with the four archives and
`SHA256SUMS`.

## How the app uses the results

1. Download the archives of one release and check them against its
   `SHA256SUMS`.
2. Unpack them into the app's native module, together with a version file
   (release tag) and the checksum file. The app build then needs no network
   and does not rebuild these libraries; it only compiles its own JNI layer
   and links these archives statically.
3. Show the licenses and the sentence "This software is based in part on the
   work of the Independent JPEG Group." in the app's open source licenses.

## Licenses

- Own files (scripts, CMake files, test, workflow): Apache License 2.0, see
  [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).
- libjpeg-turbo: [`licenses/libjpeg-turbo/`](licenses/libjpeg-turbo/)
  (`LICENSE.md`, `README.ijg` with the IJG License, `zlib-License.txt`).
  This software is based in part on the work of the Independent JPEG Group.
- piex: [`licenses/piex/LICENSE`](licenses/piex/LICENSE) (Apache License 2.0),
  Copyright 2015-2020 Google Inc.
  piex has no NOTICE file upstream; its attribution is in [`NOTICE`](NOTICE).

The third-party sources in `third_party/` keep their own license headers and
files.
