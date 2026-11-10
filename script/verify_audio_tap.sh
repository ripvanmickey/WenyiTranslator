#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/airtranslate-tap-check.XXXXXX")"
swiftc -swift-version 6 -module-cache-path "$CHECK_DIR/module-cache" \
 "$ROOT_DIR/Sources/AirTranslate/Services/CoreAudioTapCapture.swift" \
 "$ROOT_DIR/script/AudioTapChecks.swift" -o "$CHECK_DIR/check"
"$CHECK_DIR/check"
