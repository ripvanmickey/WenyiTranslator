#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/wenyi-nemotron-check.XXXXXX")"
BUILD_PATH="${SWIFT_BUILD_PATH:-$CHECK_DIR/build}"
swift build -c release --package-path "$ROOT_DIR" --scratch-path "$BUILD_PATH" --disable-sandbox
BIN_DIR="$BUILD_PATH/$(uname -m)-apple-macosx/release"
ARGS=()
for source in CoreAudioTapCapture WhisperCaptionWindow WhisperKitSpeechTranscriber SileroSpeechDetector WhisperStreamingHypothesis WhisperModelFiles NemotronSpeechTranscriber ManagedASRRuntime; do
 ARGS+=("$ROOT_DIR/Sources/AirTranslate/Services/$source.swift")
done
swiftc -O -swift-version 6 -module-cache-path "$CHECK_DIR/module-cache" -I "$BIN_DIR/Modules" \
 "${ARGS[@]}" "$ROOT_DIR/Sources/AirTranslate/Models/AppleSpeechRecognitionMetadata.swift" \
 "$ROOT_DIR/script/NemotronTransportChecks.swift" \
 "$BIN_DIR"/SileroVAD.build/*.o "$BIN_DIR"/WhisperKit.build/*.o "$BIN_DIR"/ArgmaxCore.build/*.o \
 -framework CoreML -framework Accelerate -framework AVFoundation -o "$CHECK_DIR/transport-check"
"$CHECK_DIR/transport-check"
