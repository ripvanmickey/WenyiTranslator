#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${1:-$ROOT_DIR/dist-local}"
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
BUILD_ARGS=(-c release)
if [[ "${AIRTRANSLATE_DISABLE_MANIFEST_SANDBOX:-0}" == 1 ]]; then BUILD_ARGS+=(--disable-sandbox); fi
if [[ -n "${SWIFT_CACHE_PATH:-}" ]]; then BUILD_ARGS+=(--cache-path "$SWIFT_CACHE_PATH"); fi
if [[ -n "${SWIFT_BUILD_PATH:-}" ]]; then BUILD_ARGS+=(--scratch-path "$SWIFT_BUILD_PATH"); fi
cd "$ROOT_DIR"
swift build "${BUILD_ARGS[@]}"
BINARY_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/airtranslate-local-dmg.XXXXXX")"
APP="$STAGING/文译.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY_DIR/AirTranslate" "$APP/Contents/MacOS/AirTranslate"
cp "$ROOT_DIR/Resources/WenyiIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT_DIR/Resources/WenyiIcon.png" "$APP/Contents/Resources/AppIcon.png"
cp "$ROOT_DIR/Resources/NemotronBridge.py" "$ROOT_DIR/Resources/NemotronSourceManifest.json" "$APP/Contents/Resources/"
cp -R "$ROOT_DIR/Resources/ASRRuntime" "$ROOT_DIR/Resources/ASRProject" "$APP/Contents/Resources/"
cp "$ROOT_DIR/Resources/ASRModels.py" "$ROOT_DIR/Resources/ASRModelCatalog.json" "$ROOT_DIR/Resources/ASR-Runtime-Notices.md" "$APP/Contents/Resources/"
cp "$ROOT_DIR/Resources/GraniteBridge.py" "$APP/Contents/Resources/"
cp "$ROOT_DIR/Resources/MultitalkerBridge.py" "$APP/Contents/Resources/"
cp -R "$ROOT_DIR/Resources/MultitalkerNative" "$APP/Contents/Resources/"
cp -R "$ROOT_DIR/Vendor/silero-vad-swift-main/Sources/SileroVAD/Resources/silero_vad.mlmodelc" "$APP/Contents/Resources/"
mkdir -p "$APP/Contents/Resources/ThirdParty"
cp "$ROOT_DIR/Vendor/silero-vad-swift-main/LICENSE" "$APP/Contents/Resources/ThirdParty/SileroSwift-LICENSE"
cp "$ROOT_DIR/Vendor/silero-vad-swift-main/THIRD_PARTY_NOTICES" "$APP/Contents/Resources/ThirdParty/Silero-NOTICES"
cp "$ROOT_DIR/LICENSE" "$ROOT_DIR/NOTICE" "$APP/Contents/Resources/"
BUNDLE_ID=dev.appcaster.AirTranslate.LocalQwen BUILD_NUMBER=1200 \
  bash "$ROOT_DIR/script/write_info_plist.sh" "$APP/Contents/Info.plist" release
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName 文译' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName 文译' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :NSAppTransportSecurity dict' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :NSAppTransportSecurity:NSAllowsLocalNetworking bool true' "$APP/Contents/Info.plist"
python3 "$ROOT_DIR/script/audit_macos14_bundle.py" "$APP" > "$OUTPUT_DIR/Wenyi-1200-native-audit.json"
python3 "$ROOT_DIR/script/sign_nested_runtime.py" "$APP"
codesign --force --options runtime --timestamp=none --entitlements "$ROOT_DIR/Resources/AirTranslate.entitlements" --sign - "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
ln -s /Applications "$STAGING/Applications"
cp "$ROOT_DIR/docs/LOCAL-LM-STUDIO.zh-CN.md" "$STAGING/安装与配置说明.md"
hdiutil create -volname '文译' -srcfolder "$STAGING" -format UDZO \
  "$OUTPUT_DIR/Wenyi-1.16.0-1200-arm64.dmg"
hdiutil verify "$OUTPUT_DIR/Wenyi-1.16.0-1200-arm64.dmg"
shasum -a 256 "$OUTPUT_DIR/Wenyi-1.16.0-1200-arm64.dmg" \
  > "$OUTPUT_DIR/Wenyi-1.16.0-1200-arm64.dmg.sha256"
printf 'App staging folder: %s\n' "$STAGING"
