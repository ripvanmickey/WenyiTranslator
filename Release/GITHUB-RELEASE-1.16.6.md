文译 1.16.6（构建 1268），适用于 Apple Silicon Mac，macOS 14 或更高版本。

## 本次更新

- 新增 Cloudflare Workers AI：语音在本机识别，字幕文字交给 Cloudflare 翻译；媒体模式的翻译模型也可选择 Cloudflare。
- 新增独立的 Account ID、API Token 和模型配置，可选择 Llama 3.1 8B Fast、Llama 3.3 70B Fast 或自定义 Cloudflare 文字聊天模型。
- 配置中明确控制是否允许发送字幕文字。保存配置不会调用翻译接口；点击「测试翻译」才发送固定 Hello 文本，并消耗少量用量。
- Cloudflare Token 单独保存在 macOS 钥匙串，运行时复用读取缓存；授权失败后不会随每段字幕反复弹窗，可在设置中查看或重新保存 Token 后重试。
- 按账号和模型区分媒体字幕缓存，切换模型不会混用旧译文。完整缓存继续直接复用。
- 各 AI 服务换用内置品牌 Logo，包含 OpenAI、Gemini、Meta、xAI、Qwen、Cloudflare，以及本地引擎相关的 Apple、NVIDIA 和 Index 发布方 Bilibili。保留来源与许可，使用时无需联网下载。
- Meta 官方接口保留入口并注明尚未真实账号验证；与 Cloudflare 托管的 Llama 文字模型分别配置。

## 安装与配置

下载 `Wenyi-1.16.6-1268-macOS14-arm64.dmg`，退出旧版，将「文译」拖入「应用程序」替换旧版。

Cloudflare：设置 → API 密钥 → Cloudflare Workers AI，保存 Token，填写 Account ID、选择模型，允许发送字幕文字并保存。实时字幕在「通用」中选择 Cloudflare；媒体字幕在右侧「翻译模型」中选择 Cloudflare。

## 验证与限制

- 59 项、7 组回归检查报告通过（已有可选 Nemotron GPU 冒烟检查按环境跳过），156 个原生文件的 macOS 14 兼容性检查无失败；应用签名、Logo 资源与安装包完整性均已核验。
- Cloudflare 网络测试使用本地模拟响应，尚未使用真实账号验证访问、翻译质量和延迟；未上传用户音频或字幕。Meta 官方服务同样未完成真实账号实测。
- Cloudflare 有每日免费额度，但不是所有模型都免费，具体以账号、所选模型和服务商额度为准；不会自动切换付费备用模型。
- 本包为临时签名，未经过 Apple 公证或 Mac App Store 审核，系统可能提示无法验证开发者。

源码与配置说明：[Cloudflare 接入说明](https://github.com/ripvanmickey/WenyiTranslator/blob/v1.16.6/docs/cloudflare-workers-ai.md)。
