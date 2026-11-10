#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$(mktemp -d "${TMPDIR:-/tmp}/wenyi-reasoning.XXXXXX")"
trap 'rm -rf "$CHECK"' EXIT
swiftc -swift-version 6 -target arm64-apple-macosx14.0 -module-cache-path "$CHECK/modules" \
 "$ROOT/Sources/AirTranslate/Services/LocalTranslationService.swift" \
 "$ROOT/Sources/AirTranslate/Services/JapaneseTranslationEnvelope.swift" \
 "$ROOT/script/ReasoningCompatibilityChecks.swift" -o "$CHECK/check"
"$CHECK/check"
