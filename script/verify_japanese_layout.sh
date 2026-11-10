#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$(mktemp -d "${TMPDIR:-/tmp}/wenyi-layout.XXXXXX")"
trap 'rm -rf "$CHECK"' EXIT
sed '/import AirTranslateCore/d' "$ROOT/Sources/AirTranslate/Models/CaptionLine.swift" > "$CHECK/CaptionLine.swift"
swiftc -package-name AirTranslate -module-cache-path "$CHECK/modules" \
 "$ROOT/script/JapaneseLayoutChecks.swift" "$CHECK/CaptionLine.swift" \
 "$ROOT/Sources/AirTranslateCore/TranscriptTextProcessor.swift" \
 "$ROOT/Sources/AirTranslateCore/JapaneseCaptionLayout.swift" -o "$CHECK/check"
"$CHECK/check"
