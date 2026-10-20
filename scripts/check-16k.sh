#!/usr/bin/env bash
# Copyright 2026 faebix
# SPDX-License-Identifier: Apache-2.0
#
# Checks that every LOAD segment of the given ELF shared libraries is aligned
# to at least 16 KB, as Android 15 and later require on 16 KB page devices.
#
#   scripts/check-16k.sh lib.so [lib.so ...]
#
# READELF: llvm-readelf to use (default: llvm-readelf from PATH).

set -euo pipefail

READELF="${READELF:-llvm-readelf}"
status=0
for so in "$@"; do
  aligns="$("$READELF" -lW "$so" | awk '$1 == "LOAD" { print $NF }')"
  if [ -z "$aligns" ]; then
    echo "FAIL $so: no LOAD segments found" >&2
    status=1
    continue
  fi
  ok=1
  for a in $aligns; do
    if (( a < 0x4000 )); then
      echo "FAIL $so: LOAD segment aligned to $a, needs 0x4000 or more" >&2
      ok=0
      status=1
    fi
  done
  if [ "$ok" -eq 1 ]; then
    echo "OK   $so: all LOAD segments aligned to $(echo "$aligns" | sort -u | tr '\n' ' ')"
  fi
done
exit "$status"
