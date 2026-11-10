# 文译品牌更新（1.16.0 · build 1171）

应用显示名称、主窗口标题、关于及相关提示文字改为「文译」。主版本继续 1.16.0，构建号从 1170 顺延为 1171。语音识别与翻译逻辑沿用 1170，此版不声称新增识别性能改进。

图标使用内置 image_gen 生成，以青绿色、双层对话、字幕横线和书页为意象。原始透明 PNG 保存为 outputs/文译图标.png；应用用 PNG 为 Resources/WenyiIcon.png，多尺寸 macOS 图标为 Resources/WenyiIcon.icns。生成图标后仅进行尺寸与格式转换，未使用外部 API 或 CLI 图像生成。

独立 PNG 及 ICNS 随下载交付，可作为后续图标迭代基础。下方为实际使用的最终生成提示词。

Use case: logo-brand. Create one polished macOS app icon for a Chinese live subtitle and translation application named 文译. Square 1024x1024 artwork. A luminous pale ivory speech bubble and a second smaller mint subtitle card interlocking into one distinctive abstract mark, two or three bold horizontal text strokes inside, subtle shape suggesting an open book. Refined Apple desktop icon aesthetic, deep petrol teal rounded-square tile, restrained aqua gradients, crisp generously spaced silhouette readable at 32px, subtle dimensional bevel and soft internal lighting. Single centered icon, straight-on, fills canvas with rounded square tile and transparent outer corners. No lettering, no Chinese characters, no letters, no mockup, no watermark, no extra objects. Professional quiet minimalist high contrast. Output the icon alone.

## 安装与兼容

退出旧版，解压后使用「文译.app」。改名后应用文件名不同，不会自动替换旧的 AirTranslate Local Qwen.app；不要同时运行两个副本。

应用标识、已有偏好键、钥匙串服务与模型存放目录保持原有值，继续读取之前的配置。模型目录仍在 ~/Library/Application Support/AirTranslate/WhisperKit/；本次未迁移或删除用户数据。原始项目与第三方许可证、版权声明仍保留。

## 检查

发布编译通过；图标可由 AppKit 解码，包含 16 至 1024 像素规格；核对名称、版本、构建号、可执行文件与原应用标识；应用 ZIP 解压后严格签名校验通过。未启动监听，也未重新进行音频性能测试。

交付为 macOS 26+ Apple Silicon 应用 ZIP，ad-hoc 签名，未经 Apple 公证。
