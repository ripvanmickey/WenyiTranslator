#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/airtranslate-whisper-check.XXXXXX")"
export CLANG_MODULE_CACHE_PATH="$CHECK_DIR/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CHECK_DIR/module-cache"
swift build -c release --package-path "$ROOT_DIR" --scratch-path "$CHECK_DIR/build" --disable-sandbox
BIN_DIR="$CHECK_DIR/build/$(uname -m)-apple-macosx/release"
swiftc -O -swift-version 6 -module-cache-path "$CHECK_DIR/module-cache" \
 "$ROOT_DIR/Sources/AirTranslate/Services/WhisperCaptionWindow.swift" \
 "$ROOT_DIR/script/WhisperWindowChecks.swift" -o "$CHECK_DIR/window-check"
"$CHECK_DIR/window-check"
swiftc -O -swift-version 6 -module-cache-path "$CHECK_DIR/module-cache" -I "$BIN_DIR/Modules" \
 "$ROOT_DIR/Sources/AirTranslate/Services/CoreAudioTapCapture.swift" \
 "$ROOT_DIR/Sources/AirTranslate/Services/WhisperCaptionWindow.swift" \
 "$ROOT_DIR/Sources/AirTranslate/Services/WhisperKitSpeechTranscriber.swift" \
 "$ROOT_DIR/Sources/AirTranslate/Services/SileroSpeechDetector.swift" \
 "$ROOT_DIR/Sources/AirTranslate/Services/WhisperStreamingHypothesis.swift" \
 "$ROOT_DIR/Sources/AirTranslate/Services/WhisperModelFiles.swift" \
 "$ROOT_DIR/Sources/AirTranslate/Models/AppleSpeechRecognitionMetadata.swift" \
 "$ROOT_DIR/script/WhisperPCMChecks.swift" \
 "$BIN_DIR"/SileroVAD.build/*.o "$BIN_DIR"/WhisperKit.build/*.o "$BIN_DIR"/ArgmaxCore.build/*.o \
 -framework CoreML -framework Accelerate -framework AVFoundation -o "$CHECK_DIR/pcm-check"
"$CHECK_DIR/pcm-check"

swiftc -O -swift-version 6 -module-cache-path "$CHECK_DIR/module-cache" \
 "$ROOT_DIR/Sources/AirTranslate/Services/WhisperModelFiles.swift" \
 "$ROOT_DIR/script/WhisperModelFilesChecks.swift" -o "$CHECK_DIR/model-files-check"
"$CHECK_DIR/model-files-check"

swiftc -O -swift-version 6 -module-cache-path "$CHECK_DIR/module-cache" \
 "$ROOT_DIR/Sources/AirTranslate/Services/WhisperCaptionWindow.swift" \
 "$ROOT_DIR/Sources/AirTranslate/Services/WhisperStreamingHypothesis.swift" \
 "$ROOT_DIR/script/WhisperStreamingChecks.swift" -o "$CHECK_DIR/stream-check"
"$CHECK_DIR/stream-check"

swiftc -O -swift-version 6 -module-cache-path "$CHECK_DIR/module-cache" \
 "$ROOT_DIR/Sources/AirTranslate/Services/WhisperCaptionWindow.swift" \
 "$ROOT_DIR/script/WhisperVADChecks.swift" -o "$CHECK_DIR/vad-window-check"
"$CHECK_DIR/vad-window-check"

swiftc -O -swift-version 6 -module-cache-path "$CHECK_DIR/module-cache" \
 "$ROOT_DIR/Sources/AirTranslate/Services/WhisperCaptionWindow.swift" \
 "$ROOT_DIR/script/WhisperRecoveryChecks.swift" -o "$CHECK_DIR/recovery-check"
"$CHECK_DIR/recovery-check"

swiftc -O -swift-version 6 -module-cache-path "$CHECK_DIR/module-cache" \
 "$ROOT_DIR/Sources/AirTranslate/Services/WhisperCaptionWindow.swift" \
 "$ROOT_DIR/script/WhisperTurnChecks.swift" -o "$CHECK_DIR/turn-check"
"$CHECK_DIR/turn-check"
