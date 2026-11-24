# YouTube 视频字幕预加载（测试功能）

从首页右上角的“视频字幕预加载”（SF Symbol：`play.rectangle.on.rectangle`）进入。视频继续在 Chrome 或 Safari 播放；文译读取当前视频的媒体时间显示字幕，不录制系统声音，不使用录音经过时间模拟播放进度。

## 使用

1. 输入 HTTPS YouTube 视频链接，选择原文、译文和翻译模型。
2. 字幕来源默认是“YouTube 已有字幕”。也可导入 UTF-8 SRT／VTT；文件的时间轴须对应此视频。
3. 没有字幕时，可主动选择“OpenAI 音轨识别 · 云端”。点击“开始预加载”后，公开音轨的语音片段才会发送到 OpenAI `gpt-transcribe`。识别使用片段时间轴，不承诺逐词强制对齐。API 权限、余额和网络要求适用。
4. 翻译可选择 Index 在线翻译或 OpenAI GPT-4.1 mini。已有／导入字幕只发送字幕文字；音轨识别模式另外发送音频片段。开发检查不自动读取真实密钥或调用付费 API。
5. 点击“连接当前视频”，允许文译访问所选浏览器，并保持该 YouTube 视频为当前标签页。点击“显示字幕”显示可移动、可调整大小的字幕窗。原文白色，译文黄色。
6. 在浏览器暂停、拖动或改变倍速，字幕按实际媒体时间重新定位。识别到广告或切换到另一个视频时隐藏字幕。广告检测取决于 YouTube 页面标记，页面升级后可能需适配。

## 浏览器连接

文译使用只读 Apple Events，读取当前 YouTube 页面的播放时间、暂停状态、倍速及广告状态。不会读取或导出浏览器 Cookie，不读取其他网站的正文，不控制播放。

- Chrome：在“显示 → 开发者”开启“允许来自 Apple 事件的 JavaScript”。
- Safari：在“开发”菜单开启“允许来自 Apple 事件的 JavaScript”。若没有“开发”菜单，在 Safari 设置的高级页启用开发者功能。
- 系统设置 → 隐私与安全性 → 自动化：允许文译访问所选浏览器。

这些设置由用户决定。应用不自动修改浏览器安全选项。未授权、浏览器关闭、标签页不匹配时，会显示连接说明并停止同步；不会反复弹权限窗口。

## 缓存与限制

- 字幕及已完成译文保存在 `~/Library/Application Support/Wenyi/VideoSubtitles`，按视频、语言组合、来源和翻译模型区分，支持复用及双语 SRT 导出。
- 翻译阶段中断后可重试，复用已完成的译文。音轨识别阶段尚未全部完成时停止，下次会重新识别音轨。
- 临时下载音轨在任务结束／取消时清理。缓存字幕不随安装包发布，也不提交到 GitHub。
- 从公开 YouTube 获取字幕／音轨需要网络。登录限制、地区限制、YouTube 反爬或字幕不可用时，明确报错，可改为导入已有字幕。不会自动使用浏览器账号绕过限制。直播不支持预加载完整字幕；音轨识别最长 3 小时。
- 若尚未翻译到当前播放位置，先显示已准备的原文。可等待准备完成后再播放，避免译文等待。
- 此功能不改变原有实时聆听功能和语音识别默认值。

## 视频组件及许可

首次获取公开 YouTube 字幕／音轨时，从官方 GitHub Release 下载并检查固定 SHA256：

- [yt-dlp 2026.11.23](https://github.com/yt-dlp/yt-dlp/releases/tag/2026.11.23)，文件 `yt-dlp`：`e8665ed64d6b9172773e812f891fb707a0cb1ee8d9ef4fc1acb00cabee4c5256`。项目及依赖许可见其 [LICENSE](https://github.com/yt-dlp/yt-dlp/blob/master/LICENSE) 和 [THIRD_PARTY_LICENSES](https://github.com/yt-dlp/yt-dlp/blob/master/THIRD_PARTY_LICENSES)。
- [Deno 2.9.8](https://github.com/denoland/deno/releases/tag/v2.9.8)，Apple Silicon ZIP：`9f0bf660393da2eaff044cdc7444cb08c73f235849b61d224d825a194ce7c98e`。[MIT 许可](https://github.com/denoland/deno/blob/main/LICENSE.md)。

组件安装在应用自己的 `~/Library/Application Support/Wenyi/VideoTools`。使用应用内置 Python，不修改系统 Python、浏览器扩展或用户命令行环境。组件下载失败或校验失败时停止处理。

## 检查

`bash script/verify_video_subtitles.sh [可选的公开 VTT 文件路径]` 检查链接白名单、SRT/VTT 时间轴、重叠字幕、前后拖动、空档和语音片段边界。正式构建仍保持 macOS 14 最低系统；浏览器授权、真实账号额度和云端识别质量需单独实测。
