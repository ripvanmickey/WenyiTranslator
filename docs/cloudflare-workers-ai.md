# Cloudflare Workers AI（1.16.6 / build 1268）

## 配置

1. Cloudflare 控制台 → Workers AI → Use REST API，使用模板创建 Workers AI API Token，并复制 Account ID。手动创建 Token 时按官方文档授予对应账号的 Workers AI Read / Edit 权限。
2. 文译 → 设置 → API 密钥 → Cloudflare Workers AI，保存 API Token；Token 仅存在独立的 macOS 钥匙串项 `AirTranslate.Cloudflare`，不写入偏好、字幕缓存或请求 URL。运行期间复用读取缓存；授权失败不会随每段字幕重复弹窗，可通过查看或重新保存 Token 主动重试。
3. 填写 Account ID，选择 Llama 3.1 8B Fast、Llama 3.3 70B Fast，或填写 Cloudflare 的 `@cf/...` 文字聊天模型 ID。
4. 勾选允许发送字幕文字，点击「保存配置」。Token 与配置分别保存；只有明确点击「测试翻译」才会发送固定 Hello 文本消耗少量用量。
5. 设置 → 通用 → 处理模式选择 Cloudflare Workers AI，沿用本机 Nemotron、Apple Speech 或其他已配置本地引擎识别语音。语音不发送给 Cloudflare，仅发送待翻译字幕文字。
6. 媒体模式也可在「翻译模型」中选择 Cloudflare，右侧「配置」打开相同设置。音轨识别来源仍独立选择；只有选择本地识别时音频才完全留在本机。

每天有免费 Neurons 额度，部分模型要求付费。不能把“Cloudflare 有免费额度”当成所有模型都永久免费。应用不切换付费备用模型，Cloudflare 请求本身无自动重试；连续字幕会产生多个独立请求。

## 实现边界

- 固定使用 `https://api.cloudflare.com/client/v4/accounts/{account_id}/ai/v1/chat/completions`，Account ID 限 32 位十六进制。Token 放在 Authorization Bearer 头中，拒绝重定向。
- 每段非流式返回完整译文；识别和字幕分段复用本机流程。输出上限、认证失败、限流、超时和连接错误分别报告，不回显服务端错误正文或 Token。
- 连接超时 25 秒，资源超时 30 秒。取消时不写入迟到译文。
- 实时缓存按服务地址和模型区分；媒体缓存按服务、账号和模型区分，切换不会混用译文。未完成的媒体段落可继续准备；完整缓存不要求重新访问 API。
- Meta 官方实时语音服务与 Cloudflare 托管的 Meta Llama 文字模型是两种独立服务。Meta 保留入口，标记尚未真实账号验证；不声称免费或已经可用。

## 验证

`python3 script/test_cloudflare.py --scratch-path ../macos27-preview-native-release --cache-path ../media-build-cache`

59 项、7 个测试组通过，含 Cloudflare 请求/解析/限流/超时、Keychain 命名空间、旧配置恢复、媒体缓存与原有 Gemini 分段回归；已有可选 Nemotron GPU 冒烟检查按环境跳过。所有 Cloudflare 网络测试使用本地 URLProtocol 模拟响应，未读取用户 Token 调用真实 API，也未上传用户音频或字幕。真实服务访问、翻译质量、额度和延迟尚待账号实测。

## 品牌图标

应用内置服务 Logo，来源、原始 SVG、PNG 及许可位于 `Resources/ProviderLogos`。分别标识 OpenAI、Gemini、Meta、xAI、Qwen、Cloudflare，以及 Apple、NVIDIA 和 Bilibili；不在运行时下载图标，不代表品牌背书。菜单仍使用原有原生选择框。

## 官方依据

- [REST API 与 Token 配置](https://developers.cloudflare.com/workers-ai/get-started/rest-api/)
- [OpenAI 兼容 Chat Completions](https://developers.cloudflare.com/workers-ai/configuration/open-ai-compatibility/)
- [额度与定价](https://developers.cloudflare.com/workers-ai/platform/pricing/)
- [Llama 3.3 70B](https://developers.cloudflare.com/workers-ai/models/llama-3.3-70b-instruct-fp8-fast/)
