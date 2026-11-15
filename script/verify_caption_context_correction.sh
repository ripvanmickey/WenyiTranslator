#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$(mktemp -d "${TMPDIR:-/tmp}/wenyi-caption-review.XXXXXX")"
trap 'rm -rf "$CHECK"' EXIT
swiftc -swift-version 6 -target arm64-apple-macosx14.0 -module-cache-path "$CHECK/modules" \
 "$ROOT/Sources/AirTranslate/Services/LocalTranslationService.swift" \
 "$ROOT/Sources/AirTranslate/Services/JapaneseTranslationEnvelope.swift" \
 "$ROOT/Sources/AirTranslate/Models/FloatingCaptionHistory.swift" \
 "$ROOT/Sources/AirTranslate/Models/FloatingCaptionAppearance.swift" \
 "$ROOT/script/CaptionContextCorrectionChecks.swift" -o "$CHECK/check"
"$CHECK/check"
