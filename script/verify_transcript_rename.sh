#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$(mktemp -d "${TMPDIR:-/tmp}/wenyi-rename.XXXXXX")"
trap 'rm -rf "$CHECK"' EXIT
swiftc -module-cache-path "$CHECK/modules" "$ROOT/script/TranscriptRenameChecks.swift" \
 "$ROOT/Sources/AirTranslate/Models/SavedTranscriptFileRenamer.swift" \
 "$ROOT/Sources/AirTranslate/Models/SavedTranscriptTitleStore.swift" \
 "$ROOT/Sources/AirTranslate/Models/SavedTranscript.swift" -o "$CHECK/check"
"$CHECK/check"
