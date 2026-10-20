#!/usr/bin/env bash
# Copyright 2026 faebix
# SPDX-License-Identifier: Apache-2.0
#
# Checks that third_party/ matches the upstream sources named in SOURCES:
# libjpeg-turbo against its signed release archive, piex against its git
# commit. Any difference fails the check.
#
#   scripts/verify-sources.sh
#
# Tools: curl, sha256sum, gpg, tar, git, diff.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_value() { sed -n "s/^$1 //p" "$ROOT/SOURCES"; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "== libjpeg-turbo $(source_value libjpeg-turbo.version)"
curl -fsSL -o "$tmp/libjpeg-turbo.tar.gz" "$(source_value libjpeg-turbo.url)"
curl -fsSL -o "$tmp/libjpeg-turbo.tar.gz.sig" "$(source_value libjpeg-turbo.signature)"
echo "$(source_value libjpeg-turbo.sha256)  $tmp/libjpeg-turbo.tar.gz" | sha256sum -c -

export GNUPGHOME="$tmp/gnupg"
mkdir "$GNUPGHOME"
chmod 700 "$GNUPGHOME" 2>/dev/null || true
gpg --batch --quiet --import "$ROOT/keys/libjpeg-turbo-signing-key.asc"
fingerprint="$(source_value libjpeg-turbo.signing_key_fingerprint)"
if gpg --batch --status-fd 1 --verify "$tmp/libjpeg-turbo.tar.gz.sig" "$tmp/libjpeg-turbo.tar.gz" 2>/dev/null \
  | grep -q "^\[GNUPG:\] VALIDSIG $fingerprint "; then
  echo "signature OK (key $fingerprint)"
else
  echo "FAIL: signature does not verify with key $fingerprint" >&2
  exit 1
fi

mkdir "$tmp/libjpeg-turbo"
tar -xzf "$tmp/libjpeg-turbo.tar.gz" -C "$tmp/libjpeg-turbo" --strip-components=1
diff -r "$tmp/libjpeg-turbo" "$ROOT/$(source_value libjpeg-turbo.dir)"
echo "third_party/libjpeg-turbo matches the release archive"

echo "== piex $(source_value piex.commit)"
git -c init.defaultBranch=main init -q "$tmp/piex"
git -C "$tmp/piex" -c core.autocrlf=false fetch -q --depth 1 "$(source_value piex.repository)" "$(source_value piex.commit)"
git -C "$tmp/piex" -c core.autocrlf=false checkout -q FETCH_HEAD
diff -r --exclude=.git "$tmp/piex" "$ROOT/$(source_value piex.dir)"
echo "third_party/piex matches commit $(source_value piex.commit)"
