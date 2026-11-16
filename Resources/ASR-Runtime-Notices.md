# 内置识别运行时依赖声明

CPython 3.12：许可证见 ASRRuntime/lib/python3.12/LICENSE.txt。
各 Python 依赖的许可证及原始元数据保留在对应 packages/<环境>/*.dist-info 中。
运行时不包含语音识别模型权重；下载时固定模型版本并校验大型文件。

打包时仅从安装包暂存副本移除 pip 的运行代码、指定第三方测试和手册。
随包保留许可证、软件包元数据、运行资源及原生库。

## 内置软件包

### legacy

- annotated-doc 0.0.4
- anyio 4.13.0
- certifi 2026.5.20
- cffi 2.0.0
- click 8.4.1
- filelock 3.29.3
- fsspec 2026.4.0
- h11 0.16.0
- hf-xet 1.5.1
- httpcore 1.0.9
- httpx 0.28.1
- huggingface_hub 1.18.0
- idna 3.18
- Jinja2 3.1.6
- livecaption 0.1.0
- markdown-it-py 4.2.0
- MarkupSafe 3.0.3
- mdurl 0.1.2
- miniaudio 1.71
- mlx 0.31.2
- mlx-audio 0.4.4
- mlx-lm 0.31.3
- mlx-metal 0.31.2
- numpy 2.4.6
- packaging 26.2
- protobuf 7.35.0
- pycparser 3.0
- Pygments 2.20.0
- PyYAML 6.0.3
- regex 2026.5.9
- rich 15.0.0
- safetensors 0.8.0
- scipy 1.17.1
- sentencepiece 0.2.1
- shellingham 1.5.4
- sounddevice 0.5.5
- tokenizers 0.22.2
- tqdm 4.68.2
- transformers 5.11.0
- typer 0.25.1
- typing_extensions 4.15.0

### qwen

- mlx-qwen3-asr 0.3.5

## 识别适配源码

six-ddc/livecaption，固定提交 da182e0ae496743d975d4de556d3b6e450698a5c。
具体来源及公开发行授权待确认事项见 ASRProject/UPSTREAM.txt。不把缺少明确许可证的源码擅自标记为 MIT。
## macOS 14 compatibility wheels (build 1199)
Official PyPI macosx_14_0_arm64 wheels replace the newer OS variants of MLX 0.31.2 and mlx-metal. Provenance and SHA-256 are in ASRRuntime/macos14-wheels.json. Multitalker native libraries are rebuilt with deployment target14.0 and generic ARM64 settings. Real M1/macOS14 GPU inference requires desktop testing.
