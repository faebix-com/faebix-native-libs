#!/usr/bin/env bash
# Copyright 2026 faebix
# SPDX-License-Identifier: Apache-2.0
#
# Builds libjpeg-turbo and piex as static libraries for Android, links them
# into a test library (alignment and size check) and packs one archive per ABI
# into dist/.
#
#   scripts/build-android.sh [ABI ...]      default: all four ABIs
#
# Environment:
#   ANDROID_NDK_HOME  NDK r28 or newer (required)
#   ANDROID_API       minimum API level (default: 31)
#   RELEASE_VERSION   version used in archive names and BUILDINFO (default: dev)
#   CMAKE, NINJA      tools to use (default: cmake and ninja from PATH)
#
# Tools: cmake 3.15 or newer, ninja, GNU tar, gzip, sha256sum, and nasm for
# x86 and x86_64 (the SIMD code there is written in NASM syntax).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ALL_ABIS=(arm64-v8a armeabi-v7a x86 x86_64)
API="${ANDROID_API:-31}"
VERSION="${RELEASE_VERSION:-dev}"
CMAKE="${CMAKE:-cmake}"
NINJA="${NINJA:-ninja}"
NDK="${ANDROID_NDK_HOME:?Set ANDROID_NDK_HOME to an NDK r28 or newer.}"

# CMake on Windows (Git Bash) expects C:/... paths.
native() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi
}

source_value() { sed -n "s/^$1 //p" "$ROOT/SOURCES"; }

# "<sha256>  <name>", the same on every host (Git Bash prints "*" before names).
sum_line() { echo "$(sha256sum "$1" | awk '{print $1}')  $1"; }

NDK_REV="$(sed -n 's/^Pkg\.Revision *= *//p' "$NDK/source.properties")"
case "$NDK_REV" in
  2[8-9].* | [3-9][0-9].*) ;;
  *)
    echo "NDK $NDK_REV is too old. r28 or newer aligns ELF segments to 16 KB by default." >&2
    exit 1
    ;;
esac

case "$(uname -s)" in
  Linux) HOST_TAG=linux-x86_64 ;;
  Darwin) HOST_TAG=darwin-x86_64 ;;
  MINGW* | MSYS* | CYGWIN*) HOST_TAG=windows-x86_64 ;;
  *) echo "Unknown host $(uname -s)" >&2; exit 1 ;;
esac
LLVM_BIN="$NDK/toolchains/llvm/prebuilt/$HOST_TAG/bin"
export READELF="${READELF:-$LLVM_BIN/llvm-readelf}"
STRIP="$LLVM_BIN/llvm-strip"

build_abi() {
  local abi="$1"
  local work="$ROOT/build/$abi"
  local stage="$work/stage"
  local name="faebix-native-libs-$VERSION-$abi"
  local pkg="$work/pkg/$name"

  local asm_target
  case "$abi" in
    arm64-v8a) asm_target="aarch64-linux-android$API" ;;
    armeabi-v7a) asm_target="arm-linux-androideabi$API" ;;
    x86 | x86_64) asm_target="" ;;
    *) echo "Unknown ABI $abi" >&2; exit 1 ;;
  esac

  echo "== $abi (API $API, NDK $NDK_REV)"
  rm -rf "$work"
  mkdir -p "$stage"

  # No build paths in the objects: debug info is stripped below, and the
  # prefix map covers what is left (for example __FILE__).
  local flags="-ffunction-sections -fdata-sections -ffile-prefix-map=$(native "$ROOT")=."
  local common=(
    -G Ninja
    "-DCMAKE_MAKE_PROGRAM=$(native "$(command -v "$NINJA")")"
    "-DCMAKE_TOOLCHAIN_FILE=$(native "$NDK/build/cmake/android.toolchain.cmake")"
    "-DANDROID_ABI=$abi"
    "-DANDROID_PLATFORM=android-$API"
    -DANDROID_STL=c++_static
    -DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON
    "-DCMAKE_INSTALL_PREFIX=$(native "$stage")"
    "-DCMAKE_C_FLAGS=$flags"
    "-DCMAKE_CXX_FLAGS=$flags"
  )
  if [ "$abi" = armeabi-v7a ]; then common+=(-DANDROID_ARM_MODE=arm); fi

  # libjpeg-turbo: only the libjpeg API library (no TurboJPEG API, no tools).
  local jpeg_args=(
    -DENABLE_SHARED=OFF -DENABLE_STATIC=ON
    -DWITH_TURBOJPEG=OFF -DWITH_TOOLS=OFF -DWITH_TESTS=OFF
    -DWITH_SIMD=ON -DREQUIRE_SIMD=ON
  )
  if [ -n "$asm_target" ]; then jpeg_args+=("-DCMAKE_ASM_FLAGS=--target=$asm_target"); fi
  "$CMAKE" -S "$(native "$ROOT/third_party/libjpeg-turbo")" -B "$(native "$work/libjpeg-turbo")" \
    "${common[@]}" "${jpeg_args[@]}"
  "$CMAKE" --build "$(native "$work/libjpeg-turbo")"
  "$CMAKE" --install "$(native "$work/libjpeg-turbo")"

  "$CMAKE" -S "$(native "$ROOT/cmake/piex")" -B "$(native "$work/piex")" \
    "${common[@]}" "-DPIEX_SOURCE_DIR=$(native "$ROOT/third_party/piex")"
  "$CMAKE" --build "$(native "$work/piex")"
  "$CMAKE" --install "$(native "$work/piex")"

  # Package: the two archives, their headers, the licenses and build facts.
  mkdir -p "$pkg/lib" "$pkg/include"
  cp "$(find "$stage" -name libjpeg.a | head -n 1)" "$pkg/lib/libjpeg.a"
  cp "$(find "$stage" -name libpiex.a | head -n 1)" "$pkg/lib/libpiex.a"
  "$STRIP" --strip-debug "$pkg/lib/libjpeg.a" "$pkg/lib/libpiex.a"
  local h
  for h in jpeglib.h jconfig.h jmorecfg.h jerror.h; do
    cp "$stage/include/$h" "$pkg/include/$h"
  done
  cp -R "$stage/include/piex" "$pkg/include/piex"
  cp -R "$ROOT/licenses" "$pkg/licenses"
  cp "$ROOT/NOTICE" "$pkg/NOTICE"

  # Link check and 16 KB check on a shared library that uses both archives.
  "$CMAKE" -S "$(native "$ROOT/test/linkcheck")" -B "$(native "$work/linkcheck")" \
    "${common[@]}" "-DSTAGE_DIR=$(native "$pkg")"
  "$CMAKE" --build "$(native "$work/linkcheck")"
  local so="$work/linkcheck/liblinkcheck.so"
  "$STRIP" --strip-unneeded -o "$work/liblinkcheck-stripped.so" "$so"
  "$ROOT/scripts/check-16k.sh" "$work/liblinkcheck-stripped.so"
  local so_bytes
  so_bytes="$(wc -c < "$work/liblinkcheck-stripped.so" | tr -d ' ')"

  local source_commit
  source_commit="$(git -C "$ROOT" rev-parse --verify -q HEAD || echo unknown)"
  cat > "$pkg/BUILDINFO" <<EOF
version $VERSION
abi $abi
android_api $API
ndk $NDK_REV
stl c++_static
libjpeg-turbo $(source_value libjpeg-turbo.version)
piex $(source_value piex.commit)
source_commit $source_commit
linkcheck_stripped_bytes $so_bytes
EOF

  (cd "$pkg" && find . -type f ! -name FILES.sha256 | LC_ALL=C sort | sed 's|^\./||' \
    | while read -r f; do sum_line "$f"; done > FILES.sha256)

  mkdir -p "$ROOT/dist"
  (cd "$work/pkg" && tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner \
    -cf - "$name") | gzip -n -9 > "$ROOT/dist/$name.tar.gz"
  echo "== $abi done: dist/$name.tar.gz, linkcheck $so_bytes bytes"
}

abis=("$@")
if [ ${#abis[@]} -eq 0 ]; then abis=("${ALL_ABIS[@]}"); fi
for abi in "${abis[@]}"; do build_abi "$abi"; done

(cd "$ROOT/dist" && for f in *.tar.gz; do sum_line "$f"; done > SHA256SUMS)
cat "$ROOT/dist/SHA256SUMS"
