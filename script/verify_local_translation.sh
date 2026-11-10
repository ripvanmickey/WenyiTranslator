#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/airtranslate-local-check.XXXXXX")"
# Keep compiler caches and the check executable inside this temporary folder.
swiftc -swift-version 6 -module-cache-path "$CHECK_DIR/module-cache" \
  "$ROOT_DIR/Sources/AirTranslate/Services/LocalTranslationService.swift" \
  "$ROOT_DIR/Sources/AirTranslate/Services/IncrementalLocalTranslator.swift" \
  "$ROOT_DIR/Sources/AirTranslate/Services/AudioInputTimeline.swift" \
  "$ROOT_DIR/script/LocalTranslationChecks.swift" -o "$CHECK_DIR/check"
"$CHECK_DIR/check"
printf 'Check files: %s\n' "$CHECK_DIR"

swiftc -swift-version 6 -module-cache-path "$CHECK_DIR/module-cache" \
  "$ROOT_DIR/Sources/AirTranslate/Services/AppleRecognitionTranslationPolicy.swift" \
  "$ROOT_DIR/Sources/AirTranslate/Models/AppleSpeechRecognitionMetadata.swift" \
  "$ROOT_DIR/script/RecognitionLatencyChecks.swift" -o "$CHECK_DIR/recognition-check"
"$CHECK_DIR/recognition-check"
