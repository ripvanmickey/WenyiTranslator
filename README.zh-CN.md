**1.16.11（构建 1281）** 支持媒体原文 AI 校对，悬浮字幕分批显示长段落，保存记录时跳过空字幕。[发布说明](docs/releases/1.16.11.md)。

**1.16.6 / build 1268：** 新增 Cloudflare Workers AI，本地识别和媒体字幕均可使用其文字翻译；独立配置 Account ID、Token 与模型，内置各服务 Logo。[配置与验证范围](docs/cloudflare-workers-ai.md)。

**Build 1267：** 暂停 Azure／MAI、Nari 和 Jev，移除其配置入口。下方历史版本介绍中的相关配置不适用于当前构建。[变更说明](docs/paused-integrations.md)。

<p align="center">
  <a href="#安装与配置"><img src="./docs/readme-banner.svg" alt="文译 Wenyi｜实时语音转写、双语字幕与本地翻译" width="100%"></a>
</p>

<p align="center">
  <a href="./README.md">English</a> · <strong>简体中文</strong> · <a href="./README.ja.md">日本語</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&logoColor=white" alt="Swift 6.2">
  <img src="https://img.shields.io/badge/UI-SwiftUI-147EFB?logo=apple&logoColor=white" alt="SwiftUI">
  <img src="https://img.shields.io/badge/Python-3.12-3776AB?logo=python&logoColor=white" alt="Python 3.12">
</p>

<p align="center">
  <strong>Apple Silicon</strong> · macOS 14+ · 支持 macOS 27 · 1.16.11（构建 1281）
</p>

<p align="center">
  <a href="https://github.com/ripvanmickey/WenyiTranslator/releases/latest">下载 DMG</a> ·
  <a href="https://ripvanmickey.github.io/WenyiTranslator/">产品介绍</a> ·
  <strong><a href="#安装与配置">安装与配置</a></strong> ·
  <a href="#实时字幕与本地翻译">查看功能</a> ·
  <a href="#本地构建">本地构建</a>
</p>

文译可以把 Mac 正在播放的声音或麦克风语音转成实时字幕。看外语视频、听播客或开会时，可以同时显示原文和译文，也可以将转写保存下来继续编辑。

![文译在 macOS 27 上的主窗口，底部可切换 Mac 音频、麦克风和媒体](./docs/assets/wenyi-main-zh-CN.jpg)

## 界面语言

在「**设置 → 通用**」底部的「**界面语言**」选择英语、日语、简体中文或跟随系统，界面会立即更新。字幕的原文和译文语言可单独设置。

![简体中文通用设置，显示处理模式和语音识别选项](./docs/assets/wenyi-settings-zh-CN.jpg)

## YouTube 字幕预加载与同步

视频继续在 Chrome 或 Safari 播放。选择底部「媒体」，点击「连接当前视频」读取浏览器中的视频，也可以手动输入链接。完整的本机缓存载入后即可播放。字幕来源支持 YouTube 已有字幕、SRT/VTT 导入，以及 OpenAI、Gemini 或本机 Nemotron 音轨识别。使用音轨识别时，可勾选「加载后 AI 校对原文」，已有完整缓存可直接点「校对原文」。连接浏览器需允许自动化访问，并开启「允许 Apple 事件中的 JavaScript」。详见[配置与限制](./docs/VIDEO-SUBTITLE-PRELOAD.zh-CN.md)。

## 实时字幕与本地翻译

### 实时转写与悬浮字幕

从 Mac 系统音频或麦克风采集语音，实时显示字幕。支持翻译的模式下，可在主窗口右下角切换「**仅原文**」或「**原文 + 译文**」，点击左上角的语言组合可更改原文和译文语言。悬浮字幕有单独的显示设置。macOS 26 及以上的底部控制栏使用 Liquid Glass。通过 Core Audio Tap 仅采集系统音频需要 macOS 14.2 或以上。

### 本地识别与断句

在「**设置 → 通用**」切到「**本体模型**」，可选 Nemotron 0.6B、Qwen3-ASR 或实验性的多人识别。点击识别引擎旁的齿轮进入模型管理，可下载、校验、导入或删除模型。Nemotron 和 Qwen3-ASR 使用语音活动检测（VAD）。Apple Speech 和 Apple 系统翻译需要 macOS 26 或以上。

### LM Studio 本地翻译

在「**本体模型**」中选择「**本地模型翻译**」，连接同一台 Mac 上的 LM Studio。可使用 Index-Translate 9B 预设，也可从服务的模型列表选择其他模型。设置页提供短句测试、长句测试和延迟诊断。选择本地识别和本地翻译后，音频和字幕在本机处理。

### Index 在线翻译

在「**设置 → 通用 → 处理模式**」选择「**Index 在线翻译**」。语音在 Mac 上识别，待译字幕文本发送到哔哩哔哩的 Index-Translate API。服务已预先配置。

## 致谢

感谢哔哩哔哩 [Index-Translate 项目](https://github.com/bilibili/Index-Translate#inference) 免费开放翻译 API。使用 Index 在线翻译时，文译在 Mac 上识别语音，只将待译字幕文本发送给哔哩哔哩。首次安装默认使用 Nemotron。「本体模型」和「Index 在线翻译」均可选择识别引擎和管理模型。

## 字幕记录

可以保存、编辑和重命名转写记录，在访达中定位对应的 TXT 文件。配置本地翻译模型后，还可以用它为记录补标点、分段或生成标题。

## 安装与配置

从 [GitHub Releases](https://github.com/ripvanmickey/WenyiTranslator/releases/latest) 下载 ARM64 DMG。文译支持 Apple Silicon（M1 或以上）和 macOS 14.0 或以上，包括 macOS 27。

1. 打开 DMG，把「文译」拖入「应用程序」。
2. 在「设置 → 通用」选择「本体模型」和语音识别引擎，按提示下载模型，并根据音频来源授予系统权限。
3. 需要翻译时，先在 LM Studio 加载文本模型并启动本地 API。回到文译，配置服务地址（例如 `http://localhost:1235/v1`），读取模型列表并选择实际的模型 ID。只有本地服务开启身份验证时才需要填写密钥。也可在「处理模式」直接选择「Index 在线翻译（B 站免费开源）」，无需配置 LM Studio 或密钥。
4. 点击「测试翻译」，然后选择原文和译文语言并开始监听。只看原文时可选「仅原文」。

安装包使用临时签名，Apple 公证尚未完成。

## 本地构建

使用 Apple Silicon Mac、Swift 6.2 工具链，以及包含 macOS 26 API 的 SDK。打包 DMG 使用 Xcode 27，应用的最低运行系统仍为 macOS 14。

```sh
git clone https://github.com/ripvanmickey/WenyiTranslator.git
cd WenyiTranslator
swift build -c release
```

Swift 主程序可独立编译。完整安装包还需要准备 Python/MLX 运行环境及多人识别的 ARM64 动态库。相关版本和构建脚本如下。

| 内容 | 位置 |
| --- | --- |
| Swift 依赖源码和来源说明 | [Vendor/PROVENANCE.md](./Vendor/PROVENANCE.md) |
| CPython 依赖版本 | [Resources/ASRRuntime/](./Resources/ASRRuntime/) 中的 `requirements-*.txt` |
| macOS 14 MLX wheel 来源和校验和 | [macos14-wheels.json](./Resources/ASRRuntime/macos14-wheels.json) |
| 运行环境准备 | [bundle_asr_runtime.py](./script/bundle_asr_runtime.py)、[prepare_macos14_mlx.py](./script/prepare_macos14_mlx.py) |
| 多人识别原生库 | [Resources/MultitalkerNative/](./Resources/MultitalkerNative/) 中的许可说明，打包前需提供以 macOS 14 为目标的通用 ARM64 库 |
| DMG 打包、组件检查和本地签名 | [build_local_dmg.sh](./script/build_local_dmg.sh) |

完整打包流程需要上述运行组件和可用的磁盘镜像服务。全新开发机仍需手动准备这些组件。

## 验证与限制

构建 1281 已通过签名和 156 个原生组件的最低系统版本检查。媒体回归用模拟模型响应验证了上下文校对和中断续跑。本构建尚未在 macOS 14 实机验证启动。

```sh
bash script/verify_caption_context_correction.sh
bash script/verify_reasoning_compatibility.sh
bash script/verify_joint_japanese_translation.sh
bash script/verify_transcript_polish.sh
bash script/verify_transcript_rename.sh
```

## 来源与许可

文译基于 himomohi 开发的 [AirTranslate 1.16.0](https://github.com/himomohi/AirTranslate) 开发，保留上游 [Apache-2.0 LICENSE](./LICENSE) 和 [NOTICE](./NOTICE)。第三方 SDK、运行环境及模型分别适用各自许可，详见 [Swift SDK 来源](./Vendor/PROVENANCE.md)、[ASR 运行环境说明](./Resources/ASR-Runtime-Notices.md)、[livecaption 来源](./Resources/ASRProject/UPSTREAM.txt) 和 [多人识别组件许可](./Resources/MultitalkerNative/THIRD-PARTY-LICENSES.md)。livecaption 源码的单独许可仍需确认。

