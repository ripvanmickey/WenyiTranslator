#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$(mktemp -d "${TMPDIR:-/tmp}/wenyi-titles.XXXXXX")"
trap 'rm -rf "$CHECK"' EXIT
swiftc -module-cache-path "$CHECK/modules" "$ROOT/script/SavedTranscriptTitleChecks.swift" \
 "$ROOT/Sources/AirTranslate/Models/SavedTranscriptTitleStore.swift" -o "$CHECK/storage"
"$CHECK/storage"
swiftc -swift-version 6 -module-cache-path "$CHECK/modules" "$ROOT/script/SavedTitleRequestChecks.swift" \
 "$ROOT/Sources/AirTranslate/Services/LocalTranslationService.swift" \
 "$ROOT/Sources/AirTranslate/Services/JapaneseTranslationEnvelope.swift" -o "$CHECK/request"
"$CHECK/request"
