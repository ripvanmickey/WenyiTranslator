#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/wenyi-video-checks.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
xcrun swiftc -parse-as-library \
  "$ROOT_DIR/Sources/AirTranslateCore/VideoSubtitleTimeline.swift" \
  "$ROOT_DIR/Sources/AirTranslateCore/VideoSpeechSegmentation.swift" \
  "$ROOT_DIR/script/VideoSubtitleChecks.swift" -o "$TEMP_DIR/checks"
"$TEMP_DIR/checks" "$@"
