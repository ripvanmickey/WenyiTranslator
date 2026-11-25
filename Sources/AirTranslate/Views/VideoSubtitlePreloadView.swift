import AppKit
import SwiftUI
import AirTranslateCore

struct VideoSubtitlePreloadView: View {
    @Bindable var model: VideoSubtitlePreloadStore
    @Bindable var session: TranslationSessionStore
    var onClose: () -> Void = {}
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "play.rectangle").font(.system(size: 21)).foregroundStyle(AirTranslateDesign.Palette.accent)
                    Text(AppText.ui("媒体", "Media", "メディア")).font(.system(size: 22, weight: .semibold))
                    Spacer()
                    Button(action: onClose) { Image(systemName: "xmark").font(.system(size: 13)) }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .disabled(model.isConfigurationLocked).help(AppText.ui("关闭媒体设置", "Close Media Settings", "メディア設定を閉じる"))
                        .accessibilityIdentifier("closeMediaSidebar")
                }
                note("继续在 Chrome／Safari 播放 YouTube，字幕跟随视频时间显示。")

                VStack(alignment: .leading, spacing: 8) {
                    Text("视频链接").font(.system(size: 13, weight: .semibold))
                    TextField("https://www.youtube.com/watch?v=…", text: $model.videoURL)
                        .textFieldStyle(.roundedBorder).accessibilityLabel("YouTube 视频链接")
                }.disabled(model.isConfigurationLocked)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        Text("原文").foregroundStyle(.secondary)
                        languagePicker(source: true)
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        Text("译文").foregroundStyle(.secondary)
                        languagePicker(source: false)
                    }.fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text("原文"); languagePicker(source: true) }
                        HStack { Text("译文"); languagePicker(source: false) }
                    }
                }.font(.system(size: 12)).disabled(model.isConfigurationLocked)

                VStack(alignment: .leading, spacing: 8) {
                    Text("字幕来源").font(.system(size: 13, weight: .semibold))
                    HStack(spacing: 8) {
                        Picker("字幕来源", selection: $model.input) {
                            ForEach(VideoSubtitleInput.allCases) { Text($0.title).tag($0) }
                        }.pickerStyle(.menu).labelsHidden()
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                        Spacer(minLength: 0)
                        if model.showsImportAction {
                            Button("导入…") { model.importSubtitles() }.fixedSize()
                                .accessibilityIdentifier("mediaImportSubtitles")
                        }
                        if model.input == .openAI { configureOpenAI }
                    }
                }.disabled(model.isConfigurationLocked)
                note(model.input == .openAI
                    ? "音轨片段发送到 OpenAI 识别，仅将字幕文字发送到所选翻译服务。会产生相应 API 用量。"
                    : "使用视频已有或导入的字幕，只将字幕文字发送到所选翻译服务，不上传音频。")

                VStack(alignment: .leading, spacing: 8) {
                    Text("翻译模型").font(.system(size: 13, weight: .semibold))
                    HStack(spacing: 8) {
                        Picker("翻译模型", selection: $model.translator) {
                            ForEach(VideoSubtitleTranslator.allCases) { Text($0.title).tag($0) }
                        }.pickerStyle(.menu).labelsHidden()
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                        Spacer(minLength: 0)
                        if model.translator == .openAI { configureOpenAI }
                    }
                }.disabled(model.isConfigurationLocked)

                Divider()
                HStack(spacing: 10) {
                    Button(model.prepareTitle, systemImage: "arrow.down.circle") { model.prepare() }
                        .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).disabled(!model.canPrepare)
                    if model.isPreparing { Button("停止") { model.cancel() } }
                    Spacer(minLength: 0)
                    if model.document != nil {
                        Button("导出字幕…") { model.export() }.fixedSize()
                    }
                }
                if model.isPreparing { ProgressView(value: model.progress) }
                if model.readyThroughTime > 0 {
                    Text("字幕已准备至 \(VideoSubtitlePreloadStore.timestamp(model.readyThroughTime))，可先播放。")
                        .font(.system(size: 12)).foregroundStyle(AirTranslateDesign.Palette.live)
                } else {
                    note(model.status)
                }
                if let error = model.error {
                    Label(error, systemImage: "info.circle").font(.system(size: 12)).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                Text("浏览器同步").font(.system(size: 15, weight: .semibold))
                HStack(spacing: 10) {
                    Picker("浏览器", selection: $model.browser) {
                        ForEach(VideoPlaybackBrowser.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.menu).labelsHidden().fixedSize().disabled(model.isConnected)
                    Button(model.isConnected ? "断开连接" : "连接当前视频") {
                        if model.isConnected { model.disconnect() } else { model.connect() }
                    }.fixedSize()
                }
                Text(model.isConnected ? "\(model.connectionStatus)。暂停、拖动和倍速时，左侧字幕随播放时间更新。" : model.connectionStatus)
                    .font(.system(size: 12)).foregroundStyle(model.isConnected ? Color.secondary : .orange)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Text("字幕延后")
                    Stepper(value: $model.timingOffset, in: -5...5, step: 0.1) {
                        Text(String(format: "%+.1f 秒", model.timingOffset)).monospacedDigit()
                    }.fixedSize()
                }
                note("首次连接需允许文译自动化访问，并开启浏览器“允许来自 Apple 事件的 JavaScript”。")
                HStack {
                    Button(model.overlayVisible ? "隐藏悬浮字幕" : "显示悬浮字幕") { model.toggleOverlay() }
                        .disabled(model.document == nil)
                    Spacer()
                    Image(systemName: "info.circle").foregroundStyle(.secondary)
                        .help("将视频保持为当前标签页。在 Chrome 的“显示 → 开发者”或 Safari 的“开发”菜单中开启“允许来自 Apple 事件的 JavaScript”。")
                }
            }
            .font(.system(size: 13))
            .padding(.horizontal, 28).padding(.vertical, 26)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AirTranslateDesign.Palette.canvas)
        .accessibilityIdentifier("mediaSettingsSidebar")
        .task(id: model.cacheSelectionKey) { await model.restoreCachedSelection() }
        .onChange(of: model.timingOffset) { _, _ in model.refreshCue() }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
    private func languagePicker(source: Bool) -> some View {
        Picker(source ? "原文" : "译文", selection: source ? $model.sourceLanguage : $model.targetLanguage) {
            ForEach(LanguageOption.supported) { Text($0.localizedTitle).tag($0) }
        }.pickerStyle(.menu).labelsHidden().controlSize(.small)
            .frame(width: source ? 64 : 88)
            .fixedSize(horizontal: false, vertical: true)
    }
    private var configureOpenAI: some View {
        Button(AppText.ui("配置", "Configure", "設定")) {
            session.requestAPIKeySettings(provider: .openAI)
            openSettings()
        }.fixedSize().accessibilityIdentifier("mediaConfigureOpenAI")
    }
}

struct MediaCaptionBoardView: View {
    @Bindable var model: VideoSubtitlePreloadStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Label(model.isConnected ? "已同步" : "媒体字幕", systemImage: model.isConnected ? "link.circle.fill" : "play.rectangle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(model.isConnected ? AirTranslateDesign.Palette.live : AirTranslateDesign.Palette.accent)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(AirTranslateDesign.Palette.raised, in: Capsule())
                Menu {
                    Picker("原文", selection: $model.sourceLanguage) {
                        ForEach(LanguageOption.supported) { Text($0.localizedTitle).tag($0) }
                    }
                    Picker("译文", selection: $model.targetLanguage) {
                        ForEach(LanguageOption.supported) { Text($0.localizedTitle).tag($0) }
                    }
                } label: {
                    Label("\(model.sourceLanguage.localizedTitle) → \(model.targetLanguage.localizedTitle)", systemImage: "arrow.up.arrow.down")
                        .foregroundStyle(AirTranslateDesign.Palette.accent)
                }
                .menuStyle(.borderlessButton).fixedSize()
                .disabled(model.isConfigurationLocked)
                Spacer(minLength: 12)
                Label("媒体字幕", systemImage: "play.rectangle").foregroundStyle(.secondary)
            }
            .font(.system(size: 13)).lineLimit(1)
            .padding(.horizontal, 28).frame(height: 58)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            Label("跟随视频播放 · \(VideoSubtitlePreloadStore.timestamp(model.playbackTime))", systemImage: "play.circle")
                                .foregroundStyle(AirTranslateDesign.Palette.captionSource)
                            Spacer()
                            if model.readyThroughTime > 0 {
                                Text("字幕已准备至 \(VideoSubtitlePreloadStore.timestamp(model.readyThroughTime))").foregroundStyle(.gray)
                            }
                        }.font(.system(size: 12)).monospacedDigit()

                        if model.visibleCaptionContext.isEmpty {
                            VideoSubtitleTextView(cue: nil,
                                placeholder: model.isAd ? "广告播放中" : model.isConnected ? "播放到已准备的时间段时显示字幕" : "在右侧准备字幕并连接浏览器，字幕将在这里随视频显示。",
                                sourceColor: AirTranslateDesign.Palette.captionSource,
                                  translationColor: AirTranslateDesign.Palette.captionTranslation)
                                .padding(.vertical, 18)
                        } else {
                            ForEach(model.visibleCaptionContext) { cue in
                                MediaCaptionCueView(cue: cue, isCurrent: cue.id == model.mainCaptionCue?.id,
                                                    showsTranslation: model.showsTranslation)
                                    .id(cue.id)
                            }
                        }
                    }
                    .padding(.horizontal, 40).padding(.top, 26).padding(.bottom, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: model.mainCaptionCue?.id) { _, id in
                    if let id {
                        withAnimation(reduceMotion ? nil : AirTranslateDesign.Motion.quick) { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AirTranslateDesign.Palette.captionMediaCanvas)
            .accessibilityIdentifier("mediaMainCaptionDisplay")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MediaCaptionCueView: View {
    let cue: VideoSubtitleCue
    let isCurrent: Bool
    let showsTranslation: Bool
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(VideoSubtitlePreloadStore.timestamp(cue.start)) → \(VideoSubtitlePreloadStore.timestamp(cue.end))")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.gray).monospacedDigit()
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(showsTranslation && !cue.translation.isEmpty ? cue.source + "\n" + cue.translation : cue.source, forType: .string)
                    copied = true
                } label: { Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 15)) }
                    .buttonStyle(.plain).foregroundStyle(.gray).help("复制字幕")
            }
            VideoSubtitleTextView(cue: cue, placeholder: "", showsTranslation: showsTranslation, spacing: 12,
                                  sourceColor: AirTranslateDesign.Palette.captionSource,
                                  translationColor: AirTranslateDesign.Palette.captionTranslation)
        }
        .padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay {
            RoundedRectangle(cornerRadius: 12).strokeBorder(isCurrent ? AirTranslateDesign.Palette.accent : .clear, lineWidth: 1)
        }
        .opacity(isCurrent ? 1 : 0.65)
    }
}

struct VideoSubtitleTextView: View {
    let cue: VideoSubtitleCue?
    let placeholder: String
    var showsTranslation = true
    var spacing: CGFloat = 8
    // Floating subtitles always use a dark surface; the main workspace supplies its adaptive color.
    var sourceColor: Color = FloatingCaptionAppearance.sourceTextColor
    var translationColor: Color = FloatingCaptionAppearance.translationTextColor
    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            if let cue {
                Text(cue.source).font(.system(size: 18)).foregroundStyle(sourceColor)
                if showsTranslation && !cue.translation.isEmpty {
                    Text(cue.translation).font(.system(size: 23, weight: .medium))
                        .foregroundStyle(translationColor)
                }
            } else { Text(placeholder).foregroundStyle(sourceColor.opacity(0.7)) }
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
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal")
                    Text("视频字幕")
                    Spacer(minLength: 0)
                }
                .font(.caption).foregroundStyle(.white.opacity(0.6))
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                .overlay { FloatingCaptionDragSurface().accessibilityHidden(true) }
                .help(AppText.ui("拖动这里移动字幕", "Drag here to move captions", "ここをドラッグして字幕を移動"))
                .accessibilityIdentifier("mediaCaptionDragHandle")
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
