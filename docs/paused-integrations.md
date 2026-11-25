# 暂停的集成（1.16.5，build 1267）

Azure／Microsoft Foundry／MAI、Nari、TypeSafe Jev 暂停提供：

- 通用设置不再显示 Azure／MAI、Nari 模式或 Jev 实验开关。
- API 密钥页移除这三家的配置、端点、模型和控制台入口；不再在启动时查询其钥匙串状态。
- 旧 Azure／Nari 模式不再恢复；若没有其他受支持的服务被选中，回到本机识别。语言与本地识别引擎偏好保留。
- 旧 Jev 开关始终按关闭处理，不发送候选选择请求；旧 MAI 朗读偏好回到 Apple 系统语音。
- 不删除用户钥匙串中的密钥。旧协议实现与标识保留用于兼容和以后重新接入，不代表当前版本提供这些服务；历史文档中的配置步骤不再适用。

当前模式列表：本机识别、Index 在线翻译、OpenAI、Gemini、Meta、Grok、Qwen。媒体来源保持现有选项。

验证：`python3 script/test_paused_providers.py --scratch-path ../macos27-preview-native-release --cache-path ../media-build-cache`。覆盖旧偏好迁移、禁用入口、保留受支持模型/语言及现有 Gemini/媒体/分段回归。测试不调用上述付费接口，不上传音频。
