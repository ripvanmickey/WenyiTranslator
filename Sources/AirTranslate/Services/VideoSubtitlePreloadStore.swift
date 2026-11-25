import AppKit
import CryptoKit
import Foundation
import Observation
import AirTranslateCore

enum VideoSubtitleInput: String, CaseIterable, Identifiable {
    case youtube, openAI, imported
    var id: String { rawValue }
    var title: String {
        switch self {
        case .youtube: "YouTube 已有字幕"
        case .openAI: "OpenAI 音轨识别 · 云端"
        case .imported: "导入 SRT／VTT"
        }
    }
}
enum VideoSubtitleTranslator: String, CaseIterable, Identifiable {
    case index, openAI
    var id: String { rawValue }
    var title: String { self == .index ? "Index 在线翻译" : "OpenAI · GPT-4.1 mini" }
}

@Observable @MainActor
final class VideoSubtitlePreloadStore {
    var videoURL = ""
    var sourceLanguage = LanguageOption.supported.first { $0.id == "ja-JP" }!
    var targetLanguage = LanguageOption.supported.first { $0.id == "zh-CN" }!
    var input = VideoSubtitleInput.youtube
    var translator = VideoSubtitleTranslator.index
    var browser = VideoPlaybackBrowser.chrome
    var status = "输入 YouTube 链接，先准备字幕，再连接浏览器播放。"
    var error: String?
    var isPreparing = false
    var progress = 0.0
    var document: VideoSubtitleDocument?
    var isConnected = false
    var connectionStatus = "未连接浏览器"
    var activeCue: VideoSubtitleCue?
    var playbackTime = 0.0
    private var connectedVideoID: String?
    var isPaused = true
    var isAd = false
    var timingOffset = 0.0
    var overlayVisible = false
    @ObservationIgnored private var imported: [VideoSubtitleCue] = []
    @ObservationIgnored private var importedHash = ""
    @ObservationIgnored private var preparation: Task<Void, Never>?
    @ObservationIgnored private var monitoring: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var connectionGeneration = UUID()
    @ObservationIgnored private let cache = VideoSubtitleCache()
    @ObservationIgnored private let connection = VideoBrowserConnection()
    @ObservationIgnored private let audio = VideoAudioTranscription()
    @ObservationIgnored private let openAI = OpenAITranslationService()
    @ObservationIgnored private var overlay: VideoSubtitleOverlayController?

    var translatedCount: Int { document?.cues.filter { !$0.translation.isEmpty }.count ?? 0 }
    private var inputKey: String { input == .imported ? "import:" + importedHash : input.rawValue }
    var cacheSelectionKey: String {
        [(try? YouTubeVideoReference(videoURL))?.id ?? "", sourceLanguage.id, targetLanguage.id,
         translator.rawValue, inputKey].joined(separator: "\u{0}")
    }
    private var hasMatchingDocument: Bool {
        guard let document, let video = try? YouTubeVideoReference(videoURL) else { return false }
        return document.videoID == video.id && document.sourceLanguage == sourceLanguage.id
            && document.targetLanguage == targetLanguage.id && document.provider == translator.rawValue
            && document.input == inputKey
    }
    var prepareTitle: String {
        guard hasMatchingDocument else { return "开始预加载" }
        if document?.completed == true { return "已从本机载入" }
        return document?.audioProgress?.isRecognitionComplete == false ? "继续准备字幕" : "补齐缺失字幕"
    }
    var readyThroughTime: Double {
        document?.cues.prefix(while: { !$0.translation.isEmpty }).last?.end ?? 0
    }
    var preparationSummary: String {
        guard let document else { return "" }
        if let audio = document.audioProgress, !audio.isRecognitionComplete {
            return "\(translatedCount) 段已准备 · 识别 \(audio.nextRange) / \(audio.ranges.count)"
        }
        return "\(translatedCount) / \(document.cues.count) 段已准备"
    }
    var canPrepare: Bool {
        !isPreparing && (try? YouTubeVideoReference(videoURL)) != nil
            && (input != .imported || !imported.isEmpty)
            && !(hasMatchingDocument && document?.completed == true)
    }

    /// Selection changes only read local data; missing translations need an explicit start.
    func restoreCachedSelection() async {
        guard !isPreparing else { return }
        let selection = cacheSelectionKey
        if hasMatchingDocument { return }
        document = nil; activeCue = nil; error = nil; progress = 0
        guard let video = try? YouTubeVideoReference(videoURL), input != .imported || !imported.isEmpty else {
            status = "输入 YouTube 链接，先准备字幕，再连接浏览器播放。"; return
        }
        let source = sourceLanguage.id, target = targetLanguage.id, provider = translator.rawValue, selectedInput = inputKey
        do {
            let saved = try await cache.load(videoID: video.id, source: source, target: target,
                                             provider: provider, input: selectedInput)
            guard !Task.isCancelled, !isPreparing, cacheSelectionKey == selection else { return }
            guard let saved else {
                status = "未找到匹配的本机缓存，可开始预加载。"; return
            }
            document = saved
            progress = Double(translatedCount) / Double(max(1, saved.cues.count))
            if saved.completed {
                status = "已自动载入本机缓存，无需重新下载或翻译。可直接连接浏览器显示字幕。"
            } else if saved.audioProgress?.isRecognitionComplete == false {
                status = "已自动载入本机缓存，可直接播放已准备的字幕；点击“继续准备字幕”从未完成片段继续。"
            } else {
                status = "已自动载入本机缓存，已准备的字幕可直接播放；点击“补齐缺失字幕”只处理未完成部分。"
            }
            refreshCue()
        } catch {
            guard !Task.isCancelled, !isPreparing, cacheSelectionKey == selection else { return }
            status = "本机缓存无法读取，可重新预加载。"
        }
    }

    func prepare() {
        guard canPrepare, let video = try? YouTubeVideoReference(videoURL) else { return }
        error = nil; isPreparing = true; progress = 0; activeCue = nil; document = nil
        let source = sourceLanguage, target = targetLanguage, provider = translator, selectedInput = input
        let inputKey = selectedInput == .imported ? "import:" + importedHash : selectedInput.rawValue
        let importedCues = imported
        let token = UUID(); generation = token
        preparation = Task {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("wenyi-video-" + UUID().uuidString, isDirectory: true)
            defer {
                try? FileManager.default.removeItem(at: folder)
                if generation == token { isPreparing = false; preparation = nil }
            }
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                if let saved = try await cache.load(videoID: video.id, source: source.id, target: target.id,
                                                    provider: provider.rawValue, input: inputKey) {
                    document = saved
                    if saved.completed { progress = 1; status = "已读取本机缓存，可连接浏览器显示字幕。"; refreshCue(); return }
                }
                if selectedInput == .openAI || provider == .openAI {
                    let key = try await Task.detached { try OpenAIAPIKeyStore.readAPIKey(retryAfterFailure: true) }.value
                    guard key?.isEmpty == false else { throw VideoPreloadProblem(message: "请先在设置 → API 密钥中配置 OpenAI。") }
                }
                try Task.checkCancellation()
                if selectedInput == .openAI && (document == nil || document?.audioProgress?.isRecognitionComplete == false) {
                    // Finish a cached phrase whose recognition succeeded but translation was interrupted.
                    try await translatePending(source: source, target: target, provider: provider, token: token)
                    status = "正在获取视频音轨…已有字幕可先播放。"
                    let result = try await VideoMediaTools.shared.audio(for: video, directory: folder)
                    if document == nil {
                        status = "正在划分音轨片段，随后边识别边翻译…"
                        let ranges = try await audio.prepareRanges(result.url)
                        document = .init(videoID: video.id, title: result.title, sourceLanguage: source.id,
                            targetLanguage: target.id, provider: provider.rawValue, input: inputKey, cues: [],
                            audioProgress: .init(ranges: ranges))
                        if let document { try await cache.save(document) }
                    }
                    guard let checkpoint = document?.audioProgress else { throw VideoSubtitleError.invalidAudio }
                    try await audio.transcribe(result.url, language: source, ranges: checkpoint.ranges,
                                               from: checkpoint.nextRange) { [weak self] cue, done, total in
                        guard let self, self.generation == token else { throw CancellationError() }
                        try Task.checkCancellation()
                        if let cue { self.document?.cues.append(cue) }
                        self.document?.audioProgress?.nextRange = done
                        self.document?.updatedAt = Date()
                        // Persist recognition before translating: a failed translation must not resend audio.
                        if let document = self.document { try await self.cache.save(document) }
                        self.status = "识别音轨 \(done) / \(total)，正在准备本段译文…"
                        if cue != nil, let index = self.document?.cues.indices.last {
                            try await self.translateCue(at: index, source: source, target: target, provider: provider, token: token)
                        }
                        self.progress = Double(done) / Double(max(1, total))
                        self.status = "已准备至 \(Self.timestamp(self.readyThroughTime))，可先播放；后续字幕继续处理中（\(done) / \(total)）。"
                        self.refreshCue()
                    }
                    guard self.document?.cues.isEmpty == false else {
                        throw VideoPreloadProblem(message: "音轨中未识别到可用语音。")
                    }
                    document?.completed = true
                    if let document { try await cache.save(document) }
                    status = "字幕已准备完成，重播时可直接使用本机缓存。"; progress = 1
                    return
                }
                if document == nil {
                    let title: String, cues: [VideoSubtitleCue]
                    switch selectedInput {
                    case .youtube:
                        status = "正在准备视频组件并获取原文字幕…首次需要下载组件。"
                        let result = try await VideoMediaTools.shared.subtitles(for: video, language: String(source.id.prefix(2)), directory: folder)
                        title = result.title; cues = result.cues
                    case .imported:
                        title = video.id; cues = importedCues
                    case .openAI:
                        throw VideoSubtitleError.invalidAudio
                    }
                    guard !cues.isEmpty, cues.count <= 30_000, (cues.last?.end ?? 0) <= 43_200 else {
                        throw VideoPreloadProblem(message: "字幕为空或视频过长，暂无法预加载。")
                    }
                    document = .init(videoID: video.id, title: title, sourceLanguage: source.id,
                        targetLanguage: target.id, provider: provider.rawValue, input: inputKey, cues: Self.group(cues))
                    if let document { try await cache.save(document) }
                }
                guard document?.cues.isEmpty == false else { throw VideoSubtitleError.noSubtitles }
                try await translatePending(source: source, target: target, provider: provider, token: token)
                document?.completed = true
                if let document { try await cache.save(document) }
                status = "字幕已准备完成，重播时可直接使用本机缓存。"; progress = 1
            } catch {
                if let document { try? await cache.save(document) }
                guard generation == token else { return }
                if Task.isCancelled || error is CancellationError { status = "已停止准备，已完成的字幕保留在本机。" }
                else {
                    self.error = Self.message(for: error)
                    status = "准备未完成；可重试，已完成的译文会复用。"
                }
            }
        }
    }

    private func translatePending(source: LanguageOption, target: LanguageOption,
                                  provider: VideoSubtitleTranslator, token: UUID) async throws {
        let total = document?.cues.count ?? 0
        for index in 0..<total {
            status = "正在准备译文 \(index + 1) / \(total)，已完成的字幕可先播放。"
            try await translateCue(at: index, source: source, target: target, provider: provider, token: token)
            if let audio = document?.audioProgress, !audio.isRecognitionComplete {
                progress = Double(audio.nextRange) / Double(max(1, audio.ranges.count))
            } else {
                progress = Double(index + 1) / Double(max(1, total))
            }
        }
    }

    private func translateCue(at index: Int, source: LanguageOption, target: LanguageOption,
                              provider: VideoSubtitleTranslator, token: UUID) async throws {
        try Task.checkCancellation()
        guard generation == token else { throw CancellationError() }
        guard let cue = document?.cues[index], cue.translation.isEmpty else { return }
        let translated: String
        if source == target { translated = cue.source }
        else if provider == .openAI {
            translated = try await openAI.translate(cue.source, source: source, target: target, model: .gpt41Mini)
        } else {
            var configuration = LocalTranslationConfiguration()
            configuration.enabled = true; configuration.onlineIndex = true
            translated = try await LocalTranslationService.shared.translate(cue.source, source: source.id,
                target: target.id, configuration: configuration, asSingleCaption: true)
        }
        try Task.checkCancellation()
        guard generation == token else { throw CancellationError() }
        document?.cues[index].translation = translated
        document?.updatedAt = Date()
        refreshCue()
        if let document { try await cache.save(document) }
    }

    static func timestamp(_ seconds: Double) -> String {
        let value = Int(max(0, seconds))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    func cancel() { preparation?.cancel() }
    func importSubtitles() {
        guard !isPreparing else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.plainText, .data]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let file = panel.url else { return }
        do {
            let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 20_000_000 else { throw VideoSubtitleError.invalidSubtitles }
            let data = try Data(contentsOf: file)
            imported = try VideoSubtitleTimeline.parse(data)
            importedHash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            input = .imported; error = nil; status = "已导入 \(file.lastPathComponent)，共 \(imported.count) 段。"
        } catch { self.error = Self.message(for: error) }
    }

    func connect() {
        disconnect()
        let token = UUID(); connectionGeneration = token
        let selectedBrowser = browser
        connectionStatus = "正在连接 \(selectedBrowser.title)…"
        monitoring = Task {
            var initial = true
            while !Task.isCancelled {
                do {
                    let snapshot = try await connection.read(selectedBrowser, initial: initial)
                    guard connectionGeneration == token, !Task.isCancelled else { return }
                    initial = false
                    let currentVideo = try YouTubeVideoReference(snapshot.url ?? "")
                    if videoURL.isEmpty { videoURL = currentVideo.url.absoluteString }
                    connectedVideoID = currentVideo.id
                    isConnected = true; playbackTime = snapshot.time ?? 0
                    isPaused = snapshot.paused ?? true; isAd = snapshot.ad ?? false
                    if let document, currentVideo.id != document.videoID {
                        activeCue = nil; connectionStatus = "当前视频与已准备的字幕不同，请切回原视频。"
                    } else {
                        connectionStatus = isAd ? "广告播放中，字幕暂时隐藏" : isPaused ? "已同步 · 已暂停" : "已同步 · \(snapshot.rate ?? 1)×"
                        refreshCue()
                    }
                    try await Task.sleep(for: .milliseconds(250))
                } catch {
                    guard connectionGeneration == token else { return }
                    if !Task.isCancelled { connectionStatus = Self.message(for: error) }
                    isConnected = false; activeCue = nil; return
                }
            }
        }
    }
    func disconnect() {
        connectionGeneration = UUID(); monitoring?.cancel(); monitoring = nil
        isConnected = false; activeCue = nil; connectionStatus = "未连接浏览器"
    }
    func refreshCue() {
        guard isConnected, !isAd, let document, connectedVideoID == document.videoID else { activeCue = nil; return }
        activeCue = VideoSubtitleTimeline.activeCue(in: document.cues, at: playbackTime - timingOffset)
    }
    func toggleOverlay() {
        if overlayVisible { overlay?.close(); overlayVisible = false }
        else {
            if overlay == nil { overlay = VideoSubtitleOverlayController(store: self) }
            overlay?.show(); overlayVisible = true
        }
    }
    func export() {
        guard let document else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Wenyi-\(document.videoID)-\(document.targetLanguage).srt"
        guard panel.runModal() == .OK, let file = panel.url else { return }
        do { try VideoSubtitleTimeline.srt(document.cues).write(to: file, atomically: true, encoding: .utf8) }
        catch { self.error = "字幕导出失败，请检查保存位置。" }
    }
    private static func group(_ values: [VideoSubtitleCue]) -> [VideoSubtitleCue] {
        var result: [VideoSubtitleCue] = []
        for cue in values {
            if let last = result.last, cue.start - last.end <= 0.5,
               cue.end - last.start <= 8, last.source.count + cue.source.count <= 200 {
                result[result.count - 1].source += "\n" + cue.source
                result[result.count - 1].end = cue.end
            } else { result.append(.init(id: result.count, start: cue.start, end: cue.end, source: cue.source)) }
        }
        return result
    }
    private static func message(for error: Error) -> String {
        if error is VideoSubtitleError { return "无法读取视频或字幕，请检查 YouTube 链接及 SRT／VTT 文件。" }
        return error.localizedDescription
    }
}
