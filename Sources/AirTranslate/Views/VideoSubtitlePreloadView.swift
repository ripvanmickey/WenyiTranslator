import AppKit
import SwiftUI
import AirTranslateCore

struct VideoSubtitlePreloadView: View {
    @Bindable var model: VideoSubtitlePreloadStore
    @Bindable var session: TranslationSessionStore
    @Environment(\.openSettings) private var openSettings
    @State private var showsTimeline = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("视频字幕预加载").font(.title2.bold())
                Text("继续在 Chrome／Safari 播放 YouTube，提前准备字幕并跟随播放位置显示。")
                    .foregroundStyle(.secondary)
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        TextField("https://www.youtube.com/watch?v=…", text: $model.videoURL)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("YouTube 视频链接")
                        HStack(spacing: 16) {
                            Picker("原文", selection: $model.sourceLanguage) {
                                ForEach(LanguageOption.supported) { Text($0.localizedTitle).tag($0) }
                            }.pickerStyle(.menu).fixedSize()
                            Image(systemName: "arrow.right").foregroundStyle(.secondary)
                            Picker("译文", selection: $model.targetLanguage) {
                                ForEach(LanguageOption.supported) { Text($0.localizedTitle).tag($0) }
                            }.pickerStyle(.menu).fixedSize()
                        }
                        Picker("字幕来源", selection: $model.input) {
                            ForEach(VideoSubtitleInput.allCases) { Text($0.title).tag($0) }
                        }.pickerStyle(.menu).fixedSize()
                        Picker("翻译模型", selection: $model.translator) {
                            ForEach(VideoSubtitleTranslator.allCases) { Text($0.title).tag($0) }
                        }.pickerStyle(.menu).fixedSize()
                        HStack {
                            Button("导入 SRT／VTT…", systemImage: "square.and.arrow.down") { model.importSubtitles() }
                            Button("配置 OpenAI", systemImage: "key") {
                                session.requestAPIKeySettings(provider: .openAI); openSettings()
                            }
                        }
                        Text(model.input == .openAI
                            ? "点击开始后，所选视频的音轨片段会发送到 OpenAI（gpt-transcribe）识别，字幕文字发送到所选翻译服务，产生相应 API 用量。采用语音片段时间轴，非逐词对齐。"
                            : "仅将所选视频的字幕文字发送到翻译服务，不上传音频。首次从官方来源下载视频组件，字幕缓存在本机。")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    .disabled(model.isPreparing)
                }
                HStack {
                    Button("开始预加载", systemImage: "arrow.down.circle") { model.prepare() }
                        .buttonStyle(.borderedProminent).disabled(!model.canPrepare)
                    if model.isPreparing {
                        Button("停止", systemImage: "stop.fill") { model.cancel() }
                    }
                    Spacer()
                    if let document = model.document {
                        Text("\(model.translatedCount) / \(document.cues.count) 段已准备")
                            .font(.callout).foregroundStyle(.secondary)
                        Button("导出字幕…", systemImage: "square.and.arrow.up") { model.export() }
                    }
                }
                if model.isPreparing { ProgressView(value: model.progress) }
                Text(model.status).font(.callout).foregroundStyle(.secondary)
                if let error = model.error {
                    Label(error, systemImage: "info.circle").foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                GroupBox("浏览器同步") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Picker("浏览器", selection: $model.browser) {
                                ForEach(VideoPlaybackBrowser.allCases) { Text($0.title).tag($0) }
                            }.pickerStyle(.menu).fixedSize().disabled(model.isConnected)
                            Button(model.isConnected ? "断开连接" : "连接当前视频", systemImage: "link") {
                                if model.isConnected { model.disconnect() } else { model.connect() }
                            }
                            Spacer()
                            Button(model.overlayVisible ? "隐藏字幕" : "显示字幕", systemImage: "captions.bubble") { model.toggleOverlay() }
                                .disabled(model.document == nil)
                        }
                        Text(model.connectionStatus).foregroundStyle(model.isConnected ? Color.secondary : .orange)
                            .font(.callout).fixedSize(horizontal: false, vertical: true)
                        Text("将视频保持为所选浏览器的当前标签页。首次连接需允许文译自动化访问，并在 Chrome 的“显示 → 开发者”或 Safari 的“开发”菜单中开启“允许来自 Apple 事件的 JavaScript”。暂停、拖动、倍速和广告切换都会重新校准字幕。")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Text("字幕延后")
                            Stepper(value: $model.timingOffset, in: -5...5, step: 0.1) {
                                Text(String(format: "%+.1f 秒", model.timingOffset)).monospacedDigit()
                            }.fixedSize()
                        }
                    }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                }
                VideoSubtitleTextView(cue: model.activeCue, placeholder: model.isAd ? "广告播放中" : "播放到已准备的时间段时显示字幕")
                    .padding(20).frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
                    .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 16))
                if let document = model.document {
                    DisclosureGroup("\(document.title) · 字幕时间轴", isExpanded: $showsTimeline) {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(document.cues) { cue in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(String(format: "%02d:%02d → %02d:%02d", Int(cue.start) / 60, Int(cue.start) % 60, Int(cue.end) / 60, Int(cue.end) % 60))
                                        .font(.caption).foregroundStyle(.gray)
                                    VideoSubtitleTextView(cue: cue, placeholder: "")
                                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 12))
                            }
                        }.padding(.top, 12)
                    }
                }
            }.padding(24)
        }
        .frame(minWidth: 720, minHeight: 650)
        .onChange(of: model.timingOffset) { _, _ in model.refreshCue() }
    }
}

struct VideoSubtitleTextView: View {
    let cue: VideoSubtitleCue?
    let placeholder: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let cue {
                Text(cue.source).font(.system(size: 18)).foregroundStyle(FloatingCaptionAppearance.sourceTextColor)
                if !cue.translation.isEmpty {
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
                    placeholder: model.isConnected ? (model.isAd ? "广告播放中" : "等待当前时间段的字幕…") : "请在文译中连接浏览器")
            }
        }
        .padding(18).background(Color.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 18))
    }
}
