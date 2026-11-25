import AppKit
import SwiftUI
import AirTranslateCore

/// Embedded media controls; captions are rendered by MediaCaptionBoardView in the main workspace.
struct VideoSubtitlePreloadView: View {
    @Bindable var model: VideoSubtitlePreloadStore
    @Bindable var session: TranslationSessionStore
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label(AppText.ui("媒体", "Media", "メディア"), systemImage: "play.rectangle")
                    .font(.title2.bold())
                Text("继续在 Chrome／Safari 播放 YouTube，提前准备字幕并跟随播放位置显示。")
                    .font(.callout).foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 14) {
                    TextField("https://www.youtube.com/watch?v=…", text: $model.videoURL)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("YouTube 视频链接")
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("原文", selection: $model.sourceLanguage) {
                            ForEach(LanguageOption.supported) { Text($0.localizedTitle).tag($0) }
                        }
                        Picker("译文", selection: $model.targetLanguage) {
                            ForEach(LanguageOption.supported) { Text($0.localizedTitle).tag($0) }
                        }
                    }.pickerStyle(.menu).fixedSize(horizontal: true, vertical: false)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("字幕来源").font(.headline)
                        HStack(spacing: 8) {
                            Picker("字幕来源", selection: $model.input) {
                                ForEach(VideoSubtitleInput.allCases) { Text($0.title).tag($0) }
                            }.pickerStyle(.menu).labelsHidden()
                            Spacer(minLength: 0)
                            if model.showsImportAction {
                                Button("导入…", systemImage: "square.and.arrow.down") { model.importSubtitles() }
                                    .fixedSize().accessibilityIdentifier("mediaImportSubtitles")
                            }
                            if model.input == .openAI { configureOpenAI }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("翻译模型").font(.headline)
                        HStack(spacing: 8) {
                            Picker("翻译模型", selection: $model.translator) {
                                ForEach(VideoSubtitleTranslator.allCases) { Text($0.title).tag($0) }
                            }.pickerStyle(.menu).labelsHidden()
                            Spacer(minLength: 0)
                            if model.translator == .openAI { configureOpenAI }
                        }
                    }
                    Text(model.input == .openAI
                        ? "点击预加载后，音轨片段会发送到 OpenAI（gpt-transcribe）识别，字幕文字发送到所选翻译服务，产生相应 API 用量。采用语音片段时间轴，非逐词对齐。"
                        : "仅将字幕文字发送到所选翻译服务，不上传音频。字幕缓存在本机。")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .disabled(model.isPreparing)

                Divider()
                HStack {
                    Button(model.prepareTitle, systemImage: "arrow.down.circle") { model.prepare() }
                        .buttonStyle(.borderedProminent).disabled(!model.canPrepare)
                    if model.isPreparing { Button("停止") { model.cancel() } }
                }
                if model.isPreparing { ProgressView(value: model.progress) }
                Text(model.status).font(.callout).foregroundStyle(.secondary)
                if model.readyThroughTime > 0 {
                    Label("字幕已准备至 \(VideoSubtitlePreloadStore.timestamp(model.readyThroughTime))，可先播放", systemImage: "play.circle")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if model.document != nil {
                    HStack {
                        Text(model.preparationSummary).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("导出字幕…", systemImage: "square.and.arrow.up") { model.export() }
                    }
                }
                if let error = model.error {
                    Label(error, systemImage: "info.circle").foregroundStyle(.orange)
                        .font(.callout).fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                Text("浏览器同步").font(.headline)
                HStack {
                    Picker("浏览器", selection: $model.browser) {
                        ForEach(VideoPlaybackBrowser.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.menu).labelsHidden().fixedSize().disabled(model.isConnected)
                    Button(model.isConnected ? "断开连接" : "连接当前视频", systemImage: "link") {
                        if model.isConnected { model.disconnect() } else { model.connect() }
                    }.fixedSize()
                }
                Text(model.connectionStatus).foregroundStyle(model.isConnected ? Color.secondary : .orange)
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text("字幕延后")
                    Stepper(value: $model.timingOffset, in: -5...5, step: 0.1) {
                        Text(String(format: "%+.1f 秒", model.timingOffset)).monospacedDigit()
                    }.fixedSize()
                }
                Text("将视频保持为所选浏览器的当前标签页。首次连接需允许文译自动化访问，并在 Chrome 的“显示 → 开发者”或 Safari 的“开发”菜单中开启“允许来自 Apple 事件的 JavaScript”。暂停、拖动、倍速和广告切换都会重新校准字幕。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button(model.overlayVisible ? "隐藏悬浮字幕" : "显示悬浮字幕", systemImage: "captions.bubble") { model.toggleOverlay() }
                    .disabled(model.document == nil)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AirTranslateDesign.Palette.canvas)
        .accessibilityIdentifier("mediaSettingsSidebar")
        .task(id: model.cacheSelectionKey) { await model.restoreCachedSelection() }
        .onChange(of: model.timingOffset) { _, _ in model.refreshCue() }
    }

    private var configureOpenAI: some View {
        Button(AppText.ui("配置", "Configure", "設定"), systemImage: "key") {
            session.requestAPIKeySettings(provider: .openAI)
            openSettings()
        }
        .fixedSize()
        .accessibilityIdentifier("mediaConfigureOpenAI")
    }
}

struct MediaCaptionBoardView: View {
    @Bindable var model: VideoSubtitlePreloadStore

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Label(model.isConnected ? model.connectionStatus : "媒体字幕", systemImage: "play.rectangle")
                    .foregroundStyle(AirTranslateDesign.Palette.accent)
                Text("\(model.sourceLanguage.localizedTitle) → \(model.targetLanguage.localizedTitle)")
                Spacer(minLength: 12)
                Text(model.translator.title).foregroundStyle(.secondary)
            }
            .font(AirTranslateDesign.Typography.label)
            .lineLimit(1)
            .padding(.horizontal, 24).padding(.vertical, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if model.activeCue != nil {
                        Text(VideoSubtitlePreloadStore.timestamp(model.playbackTime))
                            .font(.caption).foregroundStyle(.gray).monospacedDigit()
                    }
                    VideoSubtitleTextView(cue: model.activeCue,
                        placeholder: model.isAd ? "广告播放中" : model.isConnected ? "播放到已准备的时间段时显示字幕" : "在右侧准备字幕并连接浏览器，字幕将在这里随视频显示。",
                        showsTranslation: model.showsTranslation)
                }
                .padding(32).frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(white: 0.08))
            .accessibilityIdentifier("mediaMainCaptionDisplay")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct VideoSubtitleTextView: View {
    let cue: VideoSubtitleCue?
    let placeholder: String
    var showsTranslation = true
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let cue {
                Text(cue.source).font(.system(size: 18)).foregroundStyle(FloatingCaptionAppearance.sourceTextColor)
                if showsTranslation && !cue.translation.isEmpty {
                    Text(cue.translation).font(.system(size: 23, weight: .medium))
                        .foregroundStyle(FloatingCaptionAppearance.translationTextColor)
                }
            } else { Text(placeholder).foregroundStyle(.white.opacity(0.7)) }
        }
        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

@MainActor
final class VideoSubtitleOverlayController {
    private let panel: NSPanel
    init(store: VideoSubtitlePreloadStore) {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 760, height: 240),
            styleMask: [.borderless, .nonactivatingPanel, .resizable], backing: .buffered, defer: false)
        panel.level = .floating; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 420, height: 130)
        panel.contentView = NSHostingView(rootView: VideoSubtitleOverlayView(model: store))
        panel.isReleasedWhenClosed = false
        if let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - 380, y: screen.visibleFrame.minY + 70))
        }
    }
    func show() { panel.orderFrontRegardless() }
    func close() { panel.orderOut(nil) }
}

private struct VideoSubtitleOverlayView: View {
    @Bindable var model: VideoSubtitlePreloadStore
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("视频字幕").font(.caption).foregroundStyle(.white.opacity(0.6))
                Spacer()
                Button { model.toggleOverlay() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).foregroundStyle(.white).help("关闭字幕")
            }
            ScrollView {
                VideoSubtitleTextView(cue: model.activeCue,
                    placeholder: model.isConnected ? (model.isAd ? "广告播放中" : "等待当前时间段的字幕…") : "请在文译中连接浏览器",
                    showsTranslation: model.showsTranslation)
            }
        }
        .padding(18).background(Color.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 18))
    }
}
