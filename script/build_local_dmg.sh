#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if ! XCODE_VERSION="$(xcodebuild -version 2>/dev/null | sed -n '1p')" ||
   [[ "$XCODE_VERSION" != "Xcode 27" && "$XCODE_VERSION" != "Xcode 27."* ]] ||
   ! SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)" ||
   [[ "$SDK_VERSION" != 27 && "$SDK_VERSION" != 27.* ]]; then
  printf 'Select Xcode 27 and its macOS 27 SDK using DEVELOPER_DIR.\n' >&2
  exit 1
fi
BUILD_NUMBER=1230
APP_NAME="文译 macOS 27 预览"
ARTIFACT="Wenyi-1.16.0-${BUILD_NUMBER}-macOS27-preview-arm64"
OUTPUT_DIR="${1:-$ROOT_DIR/dist-local}"
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
BUILD_ARGS=(-c release)
if [[ "${AIRTRANSLATE_DISABLE_MANIFEST_SANDBOX:-0}" == 1 ]]; then BUILD_ARGS+=(--disable-sandbox); fi
if [[ -n "${SWIFT_CACHE_PATH:-}" ]]; then BUILD_ARGS+=(--cache-path "$SWIFT_CACHE_PATH"); fi
if [[ -n "${SWIFT_BUILD_PATH:-}" ]]; then BUILD_ARGS+=(--scratch-path "$SWIFT_BUILD_PATH"); fi
cd "$ROOT_DIR"
xcrun --sdk macosx swift build "${BUILD_ARGS[@]}"
BINARY_DIR="$(xcrun --sdk macosx swift build "${BUILD_ARGS[@]}" --show-bin-path)"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/airtranslate-local-dmg.XXXXXX")"
APP="$STAGING/$APP_NAME.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY_DIR/AirTranslate" "$APP/Contents/MacOS/AirTranslate"
cp "$ROOT_DIR/Resources/WenyiIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT_DIR/Resources/WenyiIcon.png" "$APP/Contents/Resources/AppIcon.png"
cp "$ROOT_DIR/Resources/NemotronBridge.py" "$ROOT_DIR/Resources/NemotronSourceManifest.json" "$APP/Contents/Resources/"
cp -R "$ROOT_DIR/Resources/ASRRuntime" "$ROOT_DIR/Resources/ASRProject" "$APP/Contents/Resources/"
python3 "$ROOT_DIR/script/prune_asr_runtime.py" "$APP/Contents/Resources/ASRRuntime" --apply \
  > "$OUTPUT_DIR/$ARTIFACT-runtime-prune.json"
cp "$ROOT_DIR/Resources/ASRModels.py" "$ROOT_DIR/Resources/ASRModelCatalog.json" "$ROOT_DIR/Resources/ASR-Runtime-Notices.md" "$APP/Contents/Resources/"
cp "$ROOT_DIR/Resources/MultitalkerBridge.py" "$APP/Contents/Resources/"
cp -R "$ROOT_DIR/Resources/MultitalkerNative" "$APP/Contents/Resources/"
cp -R "$ROOT_DIR/Vendor/silero-vad-swift-main/Sources/SileroVAD/Resources/silero_vad.mlmodelc" "$APP/Contents/Resources/"
mkdir -p "$APP/Contents/Resources/ThirdParty"
cp "$ROOT_DIR/Vendor/silero-vad-swift-main/LICENSE" "$APP/Contents/Resources/ThirdParty/SileroSwift-LICENSE"
cp "$ROOT_DIR/Vendor/silero-vad-swift-main/THIRD_PARTY_NOTICES" "$APP/Contents/Resources/ThirdParty/Silero-NOTICES"
cp "$ROOT_DIR/LICENSE" "$ROOT_DIR/NOTICE" "$APP/Contents/Resources/"
BUNDLE_ID=dev.appcaster.AirTranslate.MacOS27Preview BUILD_NUMBER="$BUILD_NUMBER" \
  bash "$ROOT_DIR/script/write_info_plist.sh" "$APP/Contents/Info.plist" release
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $APP_NAME" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :NSAppTransportSecurity dict' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :NSAppTransportSecurity:NSAllowsLocalNetworking bool true' "$APP/Contents/Info.plist"
python3 "$ROOT_DIR/script/audit_macos14_bundle.py" "$APP" > "$OUTPUT_DIR/$ARTIFACT-native-audit.json"
python3 "$ROOT_DIR/script/sign_nested_runtime.py" "$APP"
codesign --force --options runtime --timestamp=none --entitlements "$ROOT_DIR/Resources/AirTranslate.entitlements" --sign - "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
ln -s /Applications "$STAGING/Applications"
cp "$ROOT_DIR/docs/LOCAL-LM-STUDIO.zh-CN.md" "$STAGING/安装与配置说明.md"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -format UDZO "$OUTPUT_DIR/$ARTIFACT.dmg"
hdiutil verify "$OUTPUT_DIR/$ARTIFACT.dmg"
(cd "$OUTPUT_DIR" && shasum -a 256 "$ARTIFACT.dmg" > "$ARTIFACT.dmg.sha256")
printf 'App staging folder: %s\n' "$STAGING"
