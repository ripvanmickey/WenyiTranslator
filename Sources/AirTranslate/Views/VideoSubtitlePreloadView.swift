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
                note(AppText.ui("继续在 Chrome／Safari 播放 YouTube，字幕跟随视频时间显示。", "Play YouTube in Chrome or Safari. Captions follow the video timeline.", "Chrome／Safari で YouTube を再生すると、動画の時刻に合わせて字幕を表示します。"))

                browserSyncSection
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text(AppText.ui("视频链接", "Video link", "動画リンク")).font(.system(size: 13, weight: .semibold))
                    TextField("https://www.youtube.com/watch?v=…", text: Binding(get: { model.videoURL }, set: { model.setVideoURLManually($0) }))
                        .textFieldStyle(.roundedBorder).accessibilityLabel(AppText.ui("YouTube 视频链接", "YouTube video link", "YouTube 動画リンク"))
                }.disabled(model.isConfigurationLocked)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        Text(AppText.ui("原文", "Original", "原文")).foregroundStyle(.secondary)
                        languagePicker(source: true)
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        Text(AppText.ui("译文", "Translation", "訳文")).foregroundStyle(.secondary)
                        languagePicker(source: false)
                    }.fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text(AppText.ui("原文", "Original", "原文")); Spacer(minLength: 8); languagePicker(source: true) }
                        HStack { Text(AppText.ui("译文", "Translation", "訳文")); Spacer(minLength: 8); languagePicker(source: false) }
                    }
                }.font(.system(size: 12)).disabled(model.isConfigurationLocked)

                Toggle(AppText.ui("根据标题自动选择原文语言", "Select original language from the title", "タイトルから原文言語を自動選択"),
                       isOn: Binding(get: { model.automaticallySelectsSourceLanguageFromTitle }, set: { model.setTitleLanguageSelectionEnabled($0) }))
                    .toggleStyle(.checkbox).disabled(model.isConfigurationLocked)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("mediaSourceLanguageFromTitle")
                note(model.titleLanguageStatus)

                VStack(alignment: .leading, spacing: 8) {
                    Text(AppText.ui("字幕来源", "Caption source", "字幕ソース")).font(.system(size: 13, weight: .semibold))
                    HStack(spacing: 8) {
                        Picker(AppText.ui("字幕来源", "Caption source", "字幕ソース"), selection: $model.input) {
                            ForEach(VideoSubtitleInput.allCases) { Text($0.title).tag($0) }
                        }.pickerStyle(.menu).labelsHidden()
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                        Spacer(minLength: 0)
                        if model.showsImportAction {
                            Button(AppText.ui("导入…", "Import…", "読み込む…")) { model.importSubtitles() }.fixedSize()
                                .accessibilityIdentifier("mediaImportSubtitles")
                        }
                        if model.input == .openAI { configureOpenAI }
                        if model.showsGeminiConfiguration {
                            Button(AppText.ui("配置", "Configure", "設定")) {
                                session.requestAPIKeySettings(provider: .gemini)
                                openSettings()
                            }.fixedSize().accessibilityIdentifier("mediaConfigureGemini")
                        }
                        if model.input == .nemotron {
                            Button(AppText.ui("模型", "Model", "モデル")) {
                                session.requestGeneralSettings()
                                openSettings()
                            }.fixedSize().accessibilityIdentifier("mediaNemotronModelSettings")
                        }
                    }
                }.disabled(model.isConfigurationLocked)
                note(model.input == .nemotron
                    ? AppText.ui("音轨由本机 Nemotron 识别，不上传音频；仅将字幕文字发送给所选翻译服务。需先下载 Nemotron 模型。", "Nemotron recognizes audio on this Mac without uploading it. Only text is sent to the translation service. Download the Nemotron model first.", "Nemotron がこの Mac で音声を認識し、音声はアップロードしません。翻訳サービスにはテキストのみを送信します。先に Nemotron モデルをダウンロードしてください。")
                    : model.input == .gemini
                    ? AppText.ui("音轨按语音分段发送到 Gemini 3.5 Transcribe 识别，字幕文字发送到所选翻译服务。会产生相应 API 用量。", "Speech segments are sent to Gemini 3.5 Transcribe. Caption text is sent to your translation service. API usage applies.", "発話ごとの音声を Gemini 3.5 Transcribe に送信し、字幕テキストを選択した翻訳サービスに送信します。API 利用量が発生します。")
                    : model.input == .openAI
                    ? AppText.ui("音轨片段发送到 OpenAI 识别，仅将字幕文字发送到所选翻译服务。会产生相应 API 用量。", "Audio segments are sent to OpenAI for recognition. Only caption text is sent to the translation service. API usage charges apply.", "音声区間を OpenAI に送信して認識します。翻訳サービスには字幕テキストのみを送信します。API 利用料金が発生します。")
                    : AppText.ui("使用视频已有或导入的字幕，只将字幕文字发送到所选翻译服务，不上传音频。", "Use existing or imported captions. Only text is sent to the translation service; audio is not uploaded.", "既存または読み込んだ字幕を使用します。翻訳サービスにはテキストだけを送信し、音声はアップロードしません。"))

                VStack(alignment: .leading, spacing: 8) {
                    Text(AppText.ui("翻译模型", "Translation model", "翻訳モデル")).font(.system(size: 13, weight: .semibold))
                    HStack(spacing: 8) {
                        Picker(AppText.ui("翻译模型", "Translation model", "翻訳モデル"), selection: $model.translator) {
                            ForEach(VideoSubtitleTranslator.allCases) { Text($0.title).tag($0) }
                        }.pickerStyle(.menu).labelsHidden()
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                        Spacer(minLength: 0)
                        if model.translator == .openAI { configureOpenAI }
                        if model.translator == .cloudflare {
                            Button(AppText.ui("配置", "Configure", "設定")) {
                                session.requestAPIKeySettings(provider: .cloudflare)
                                openSettings()
                            }.fixedSize().accessibilityIdentifier("mediaConfigureCloudflare")
                        }
                    }
                }.disabled(model.isConfigurationLocked)

                Divider()
                ViewThatFits(in: .horizontal) {
                    preparationActions.fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 8) {
                        prepareButton
                        if model.isPreparing { Button(AppText.ui("停止", "Stop", "停止")) { model.cancel() } }
                        if model.document != nil { exportButton }
                    }
                }
                if model.isPreparing { ProgressView(value: model.progress) }
                if model.readyThroughTime > 0 {
                    Text(AppText.ui("字幕已准备至 \(VideoSubtitlePreloadStore.timestamp(model.readyThroughTime))，可先播放。", "Ready through \(VideoSubtitlePreloadStore.timestamp(model.readyThroughTime)). You can start playback.", "\(VideoSubtitlePreloadStore.timestamp(model.readyThroughTime)) まで準備済み。再生を開始できます。"))
                        .font(.system(size: 12)).foregroundStyle(AirTranslateDesign.Palette.live)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    note(model.status)
                }
                if let error = model.error {
                    Label(error, systemImage: "info.circle").font(.system(size: 12)).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.system(size: 13))
            .padding(.horizontal, 28).padding(.vertical, 26)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AirTranslateDesign.Palette.canvas)
        .accessibilityIdentifier("mediaSettingsSidebar")
        .task(id: "\(model.browser.rawValue):\(model.automaticallyReadsBrowserTab)") { await model.monitorCurrentBrowserTab() }
        .task(id: model.cacheSelectionKey) { await model.restoreCachedSelection() }
        .onChange(of: model.timingOffset) { _, _ in model.refreshCue() }
    }

    private var browserSyncSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppText.ui("浏览器同步", "Browser sync", "ブラウザ同期")).font(.system(size: 15, weight: .semibold))
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { browserPicker; connectionButton }.fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 8) { browserPicker; connectionButton }
            }
            Toggle(AppText.ui("自动读取当前标签页", "Read the current tab automatically", "現在のタブを自動で読み取る"), isOn: $model.automaticallyReadsBrowserTab)
                .toggleStyle(.checkbox).disabled(model.isConfigurationLocked)
                .accessibilityIdentifier("mediaReadCurrentTabAutomatically")
            Text(model.browserTabStatus).font(.system(size: 12))
                .foregroundStyle(model.browserTabNeedsAttention && model.automaticallyReadsBrowserTab ? Color.orange : .secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(model.isConnected ? AppText.ui("\(model.connectionStatus)。暂停、拖动和倍速时，左侧字幕随播放时间更新。", "\(model.connectionStatus). Captions follow pauses, seeking, and playback speed.", "\(model.connectionStatus)。一時停止、シーク、再生速度の変更に合わせて字幕を更新します。") : model.connectionStatus)
                .font(.system(size: 12)).foregroundStyle(model.isConnected ? Color.secondary : .orange)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Text(AppText.ui("字幕延后", "Caption delay", "字幕の遅延"))
                Stepper(value: $model.timingOffset, in: -5...5, step: 0.1) {
                    Text(String(format: AppText.ui("%+.1f 秒", "%+.1f s", "%+.1f 秒"), model.timingOffset)).monospacedDigit()
                }.fixedSize()
            }
            BrowserSyncSetupGuide(browser: model.browser)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var prepareButton: some View {
        Button(model.prepareTitle, systemImage: "arrow.down.circle") { model.prepare() }
            .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).disabled(!model.canPrepare)
    }
    private var exportButton: some View {
        Button(AppText.ui("导出字幕…", "Export…", "書き出す…")) { model.export() }
    }
    private var preparationActions: some View {
        HStack(spacing: 10) {
            prepareButton
            if model.isPreparing { Button(AppText.ui("停止", "Stop", "停止")) { model.cancel() } }
            if model.document != nil { exportButton }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var browserPicker: some View {
        Picker(AppText.ui("浏览器", "Browser", "ブラウザ"), selection: $model.browser) {
            ForEach(VideoPlaybackBrowser.allCases) { Text($0.title).tag($0) }
        }.pickerStyle(.menu).labelsHidden().disabled(model.isConfigurationLocked)
    }
    private var connectionButton: some View {
        Button(model.isConnected || model.isConnecting ? AppText.ui("断开连接", "Disconnect", "接続を解除") : AppText.ui("连接当前视频", "Connect video", "動画に接続")) {
            if model.isConnected || model.isConnecting { model.disconnect() } else { model.connect(prepareCaptions: true) }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
    private func languagePicker(source: Bool) -> some View {
        Picker(source ? AppText.ui("原文", "Original", "原文") : AppText.ui("译文", "Translation", "訳文"), selection: source ? Binding(get: { model.sourceLanguage }, set: { model.setSourceLanguageManually($0) }) : $model.targetLanguage) {
            ForEach(LanguageOption.supported) { Text($0.localizedTitle).tag($0) }
        }.pickerStyle(.menu).labelsHidden().controlSize(.small)
            .frame(width: InterfaceLocalization.interfaceLanguage == .english ? (source ? 110 : 150) : (source ? 86 : 120))
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
                Label(model.isConnected ? AppText.ui("已同步", "Synced", "同期済み") : AppText.ui("媒体字幕", "Media captions", "メディア字幕"), systemImage: model.isConnected ? "link.circle.fill" : "play.rectangle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(model.isConnected ? AirTranslateDesign.Palette.live : AirTranslateDesign.Palette.accent)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(AirTranslateDesign.Palette.raised, in: Capsule())
                Menu {
                    Picker(AppText.ui("原文", "Original", "原文"), selection: Binding(get: { model.sourceLanguage }, set: { model.setSourceLanguageManually($0) })) {
                        ForEach(LanguageOption.supported) { Text($0.localizedTitle).tag($0) }
                    }
                    Picker(AppText.ui("译文", "Translation", "訳文"), selection: $model.targetLanguage) {
                        ForEach(LanguageOption.supported) { Text($0.localizedTitle).tag($0) }
                    }
                } label: {
                    Label("\(model.sourceLanguage.localizedTitle) → \(model.targetLanguage.localizedTitle)", systemImage: "arrow.up.arrow.down")
                        .foregroundStyle(AirTranslateDesign.Palette.accent)
                }
                .menuStyle(.borderlessButton).fixedSize()
                .disabled(model.isConfigurationLocked)
                Spacer(minLength: 12)
                Label(AppText.ui("媒体字幕", "Media captions", "メディア字幕"), systemImage: "play.rectangle").foregroundStyle(.secondary)
            }
            .font(.system(size: 13)).lineLimit(1)
            .padding(.horizontal, 28).frame(height: 58)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            Label(AppText.ui("跟随视频播放 · \(VideoSubtitlePreloadStore.timestamp(model.playbackTime))", "Video time · \(VideoSubtitlePreloadStore.timestamp(model.playbackTime))", "動画の時刻・\(VideoSubtitlePreloadStore.timestamp(model.playbackTime))"), systemImage: "play.circle")
                                .foregroundStyle(AirTranslateDesign.Palette.captionSource)
                            Spacer()
                            if model.readyThroughTime > 0 {
                                Text(AppText.ui("字幕已准备至 \(VideoSubtitlePreloadStore.timestamp(model.readyThroughTime))", "Ready through \(VideoSubtitlePreloadStore.timestamp(model.readyThroughTime))", "\(VideoSubtitlePreloadStore.timestamp(model.readyThroughTime)) まで準備済み")).foregroundStyle(.gray)
                            }
                        }.font(.system(size: 12)).monospacedDigit()
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)

                        if model.visibleCaptionContext.isEmpty {
                            VideoSubtitleTextView(cue: nil,
                                placeholder: model.isAd ? AppText.ui("广告播放中", "Ad playing", "広告再生中") : model.isConnected ? AppText.ui("播放到已准备的时间段时显示字幕", "Captions appear when playback reaches a prepared segment.", "準備済みの区間に達すると字幕を表示します。") : AppText.ui("在右侧准备字幕并连接浏览器，字幕将在这里随视频显示。", "Prepare captions on the right and connect your browser to show synchronized captions here.", "右側で字幕を準備し、ブラウザに接続すると、動画に合わせてここに字幕を表示します。"),
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
                    .buttonStyle(.plain).foregroundStyle(.gray).help(AppText.ui("复制字幕", "Copy captions", "字幕をコピー"))
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
    @State private var measuredCaptionHeight: CGFloat = 48
    private var preferredHeight: CGFloat { FloatingCaptionAppearance.compactWindowHeight(contentHeight: measuredCaptionHeight) }
    var body: some View {
        let style = UnifiedFloatingCaptionStyle(session: model.captionSession)
        UnifiedFloatingCaptionSurface(title: AppText.ui("视频字幕", "Video captions", "動画字幕"),
            style: style, close: { model.toggleOverlay() }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let cue = model.activeCue {
                        let text = VideoSubtitleTimeline.floatingText(for: cue, at: model.playbackTime - model.timingOffset,
                            showsSource: style.mode != .translation,
                            showsTranslation: model.showsTranslation && style.mode != .original)
                        UnifiedFloatingCaptionBlock(source: text.source, translation: text.translation, style: style)
                    } else {
                        Text(model.isConnected ? (model.isAd ? AppText.ui("广告播放中", "Ad playing", "広告再生中") : AppText.ui("等待当前时间段的字幕…", "Waiting for captions at this position…", "現在の区間の字幕を待機中…")) : AppText.ui("请在文译中连接浏览器", "Connect your browser in Wenyi.", "文訳でブラウザに接続してください。"))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measuredCaptionHeight = $0 }
            }
            .frame(height: preferredHeight - FloatingCaptionAppearance.compactWindowChromeHeight)
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
        .background(FloatingWindowConfigurator(preferredContentHeight: preferredHeight,
            minimumWindowSize: FloatingCaptionWindowController.minimumWindowSize,
            keepsAboveOtherWindows: model.captionSession?.keepsFloatingCaptionAboveOtherWindows ?? true,
            hasCaptionText: model.activeCue != nil))
    }
}
