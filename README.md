<p align="center">
  <a href="#installation-and-setup"><img src="./docs/readme-banner.svg" alt="Wenyi — live transcription, bilingual captions, and local translation" width="100%"></a>
</p>

<p align="center">
  <strong>English</strong> · <a href="./README.zh-CN.md">简体中文</a> · <a href="./README.ja.md">日本語</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&logoColor=white" alt="Swift 6.2">
  <img src="https://img.shields.io/badge/UI-SwiftUI-147EFB?logo=apple&logoColor=white" alt="SwiftUI">
  <img src="https://img.shields.io/badge/Python-3.12-3776AB?logo=python&logoColor=white" alt="Python 3.12">
</p>

<p align="center">
  <strong>Apple Silicon</strong> · macOS 14+ · 1.16.0 (build 1202)
</p>

<p align="center">
  <strong><a href="#installation-and-setup">Installation and setup</a></strong> ·
  <a href="#live-captions-and-local-translation">Features</a> ·
  <a href="#build-locally">Build locally</a>
</p>

Wenyi turns Mac system audio or microphone input into live captions. Display the original and translated text together while watching a video, listening to a podcast, or joining a meeting, then save the transcript for editing.

## Live captions and local translation

### Live transcription and floating captions

Capture system audio or microphone input and follow the transcript as people speak. With translation enabled, show the translation alone or both languages in the main or floating window. Audio-only system capture via Core Audio Tap requires macOS 14.2 or later.

### Local speech recognition and segmentation

Choose Nemotron 0.6B, Granite Speech 2B, Qwen3-ASR, or experimental multi-speaker recognition. Download, import, or delete recognition models within the app. Nemotron and Qwen3-ASR offer voice activity detection (VAD) presets and custom settings that apply the next time a session starts. Apple Speech and Apple system translation require macOS 26 or later.

### Local translation with LM Studio

Wenyi sends the recognized text to LM Studio on the same Mac. The settings include short- and long-sentence translation tests and caption latency diagnostics. With local recognition and local translation selected, audio and text are processed on your Mac.

Build 1202 adds **contextual caption correction**. While translation is idle, Wenyi uses later speech to check recent finalized captions for homophone mistakes and updates the original and translation together when it finds a correction. New captions take priority. You can turn this feature off under Settings → General.

## Saved transcripts

Save, edit, or rename transcripts and reveal the corresponding TXT files in Finder. A configured local translation model can restore punctuation, split text into paragraphs, or suggest a title.

## Installation and setup

Requires Apple Silicon (M1 or later) and macOS 14.0 or later. This repository hosts the source code. Test installers are distributed separately.

1. Open the DMG and drag Wenyi into Applications. If you have the ZIP, extract it and move the app into Applications.
2. In Settings → General, select local mode and a speech recognition engine. Download the model when prompted and grant the permissions required by your audio source.
3. For translation, load a text model in LM Studio and start its local API. In Wenyi, enter the service address, such as `http://localhost:1235/v1`, fetch the model list, and choose the model ID shown there. Enter a key if the local server requires authentication.
4. Test translation, choose the source and target languages, and start listening. Select original-only output for transcription.

The test packages use a local ad hoc signature and have yet to be notarized by Apple.

## Build locally

Use an Apple Silicon Mac, the Swift 6.2 toolchain, and an SDK that includes macOS 26 APIs. The app deployment target is macOS 14.

```sh
git clone https://github.com/ripvanmickey/WenyiTranslator.git
cd WenyiTranslator
swift build -c release
```

The main Swift executable builds independently. A complete installer also needs the Python/MLX runtime and ARM64 libraries for multi-speaker recognition.

| Item | Location |
| --- | --- |
| Vendored Swift dependencies and provenance | [Vendor/PROVENANCE.md](./Vendor/PROVENANCE.md) |
| CPython dependency versions | `requirements-*.txt` in [Resources/ASRRuntime/](./Resources/ASRRuntime/) |
| macOS 14 MLX wheels and checksums | [macos14-wheels.json](./Resources/ASRRuntime/macos14-wheels.json) |
| Runtime setup | [bundle_asr_runtime.py](./script/bundle_asr_runtime.py), [prepare_macos14_mlx.py](./script/prepare_macos14_mlx.py) |
| Multi-speaker native libraries | License information in [Resources/MultitalkerNative/](./Resources/MultitalkerNative/). Provide generic ARM64 libraries targeting macOS 14 for packaging. |
| DMG packaging, component checks, and local signing | [build_local_dmg.sh](./script/build_local_dmg.sh) |

On a fresh development Mac, prepare the runtime and libraries manually before packaging. The packaging script also needs working disk image services.

## Verification and limits

Build 1202 passed compilation, signature and DMG integrity checks, and macOS 14 minimum-version checks for 296 native components. Contextual correction passed tests with a simulated service. Correction accuracy and latency in real Japanese conversations, and end-to-end behavior on an M1 Mac running macOS 14, remain to be tested.

```sh
bash script/verify_caption_context_correction.sh
bash script/verify_reasoning_compatibility.sh
bash script/verify_joint_japanese_translation.sh
bash script/verify_transcript_polish.sh
bash script/verify_transcript_rename.sh
```

## Credits and licensing

Wenyi is based on [AirTranslate 1.16.0](https://github.com/himomohi/AirTranslate) and retains its [Apache-2.0 license](./LICENSE) and [NOTICE](./NOTICE). See the separate notices for the [Swift SDKs](./Vendor/PROVENANCE.md), [ASR runtime](./Resources/ASR-Runtime-Notices.md), [livecaption source](./Resources/ASRProject/UPSTREAM.txt), and [multi-speaker components](./Resources/MultitalkerNative/THIRD-PARTY-LICENSES.md). The standalone license for the livecaption source still needs confirmation.
