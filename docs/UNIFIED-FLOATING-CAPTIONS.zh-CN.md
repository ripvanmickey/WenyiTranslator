# 统一悬浮字幕（1264）

媒体与 Mac 音频／麦克风实时字幕共用 SwiftUI 字幕文字和面板组件，设置预览也使用同一个文字组件。

- 固定系统字体、黑色半透明底、白色原文、黄色译文，默认原文在上。
- 移除日常／影院／讲座／高对比度／明亮画面等预设，以及字体家族、文字特效、颜色、上下顺序等复杂选择。
- 字号、行间距、窗口高度、对齐、背景不透明度、置顶置于默认收起的「高级选项」。媒体悬浮窗同步读取这些设置。
- 预览采用 16:9 视频画面，宽窗口左右排列、窄窗口上下排列；修改立即生效。参考 FluentRead 的字幕预览布局，独立以 SwiftUI 实现，未复制其源代码或资源。
- 保留实时字幕稳定更新、媒体逐句同步、文本滚动、拖动跨屏及关闭功能。
- 旧预设的字体、颜色及特效保存值不再影响实际悬浮显示；已有字号、间距、透明度、对齐等高级设置沿用。恢复默认使用媒体样式基准。

参考：
[FluentRead 字幕外观设置](https://github.com/FluentRead/FluentRead/blob/main/src/features/settings/ui/VideoSubtitleAppearanceSettings.vue)
[FluentRead 预览布局说明](https://github.com/FluentRead/FluentRead/blob/main/docs/reports/selection-media-settings-20261005/subtitle-preview.md)

本次同时修复识别模型齿轮：模型管理从设置窗口根视图展示，避开嵌套配置弹窗的展示冲突；1263 已实测打开、关闭及再次打开。
