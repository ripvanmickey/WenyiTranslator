# 文译（Wenyi）

适用于 Apple Silicon Mac 的实时语音转写与翻译应用，基于 [AirTranslate 1.16.0](https://github.com/himomohi/AirTranslate) 修改。当前源码对应 **1.16.0 / 构建 1200**。

## 功能与要求

- macOS 14.0 及以上、M1 及以上；macOS 14.2 起支持纯系统音频 Tap。
- 本地识别：Nemotron 0.6B、Granite Speech 2B、Qwen3-ASR；实验多人识别。识别模型在应用内按需下载、导入和删除。
- 独立 LM Studio 提供本地文本翻译；支持流式字幕、原文/译文显示、悬浮字幕和延迟诊断。
- 保存、编辑和重命名转写记录；可用本地模型整理标点、分段和生成标题。
- macOS 26 保留 Apple Speech / 系统翻译；较旧系统使用第三方本地识别和 LM Studio 翻译。

## 开发构建

需要 Apple Silicon Mac、Swift 6.2 工具链和相应 macOS SDK。部署目标为 macOS 14，但构建所需 SDK 和最低运行系统不是同一概念。

```sh
swift build -c release
```

Swift 依赖源码位于 `Vendor/`，来源与修改说明见 `Vendor/PROVENANCE.md`。Swift 主程序可独立编译；**完整独立安装包还需要准备 Python/MLX 运行环境及多人引擎原生库**，这些生成产物不放入 Git。

- `Resources/ASRRuntime/requirements-*.txt`：构建 1200 的三个 Python 依赖环境版本记录。
- `Resources/ASRRuntime/macos14-wheels.json`：macOS 14 MLX wheel 来源与 SHA-256。
- `script/bundle_asr_runtime.py`：从开发者准备的 CPython 3.12 与三个依赖环境生成可搬移运行环境。
- `script/prepare_macos14_mlx.py`：准备 macOS 14 对应 MLX 组件。
- `Resources/MultitalkerNative/`：许可文本；打包前需提供按 macOS 14 / 通用 ARM64 编译的 transcribe.cpp 与 ggml 动态库。
- `script/build_local_dmg.sh`：完成上述准备后进行打包、组件检查及本地签名；需要可用的磁盘镜像服务。

此仓库提供当前开发源码，**尚不包含从全新开发机自动生成完整 ASR 运行环境的一键流程**。预构建 Python 解释器、已安装依赖、模型权重、安装包和用户记录均不提交。

## 本地翻译

启动 LM Studio 服务，在文译中填写服务地址（例如 `http://localhost:1235/v1`）、准确模型 ID 和可选密钥，再点击「测试翻译」。构建 1200 修复 Qwen3-Coder 不支持 reasoning 配置时的 HTTP 400；支持该能力的 Qwen 模型仍请求关闭思考。

## 验证与限制

本地构建、签名和 296 个原生组件的 macOS 14 最低版本检查已通过；M1 + macOS 14 实机端到端表现仍需测试。构建 1200 的 reasoning 兼容性模拟服务检查和日语联合输出检查通过，不能替代所有模型的真实推理测试。当前安装包采用本地临时签名，未完成 Apple 公证。

回归脚本在 `script/`，例如：

```sh
bash script/verify_reasoning_compatibility.sh
bash script/verify_joint_japanese_translation.sh
bash script/verify_transcript_polish.sh
bash script/verify_transcript_rename.sh
```

## 来源与许可

保留上游 Apache-2.0 `LICENSE` 和 `NOTICE`。第三方 SDK、运行环境及模型各自适用原许可，参见 `Vendor/PROVENANCE.md`、`Resources/ASR-Runtime-Notices.md`、`Resources/ASRProject/UPSTREAM.txt` 和 `Resources/MultitalkerNative/THIRD-PARTY-LICENSES.md`。livecaption 来源的单独许可情况尚需确认，不能将所有第三方内容统一视为 Apache-2.0。
