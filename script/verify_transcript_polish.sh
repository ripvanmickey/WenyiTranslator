#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$(mktemp -d "${TMPDIR:-/tmp}/wenyi-polish.XXXXXX")"
trap 'rm -rf "$CHECK"' EXIT
swiftc -swift-version 6 -module-cache-path "$CHECK/modules" "$ROOT/script/TranscriptPolishChecks.swift" \
 "$ROOT/Sources/AirTranslate/Services/LocalTranslationService.swift" \
 "$ROOT/Sources/AirTranslate/Services/JapaneseTranslationEnvelope.swift" -o "$CHECK/check"
"$CHECK/check"
