import AppKit
import CryptoKit
import Foundation
import Observation
import UniformTypeIdentifiers
import AirTranslateCore

enum VideoSubtitleInput: String, CaseIterable, Identifiable {
    case youtube, openAI, gemini, nemotron, imported
    var id: String { rawValue }
    var requiresAudioRecognition: Bool { self == .openAI || self == .gemini || self == .nemotron }
    var audioEngine: VideoAudioRecognitionEngine { self == .nemotron ? .nemotron : self == .gemini ? .gemini : .openAI }
    var title: String {
        switch self {
        case .youtube: AppText.ui("YouTube 已有字幕", "YouTube captions", "YouTube 字幕")
        case .openAI: AppText.ui("OpenAI 音轨识别 · 云端", "OpenAI audio recognition · Cloud", "OpenAI 音声認識・クラウド")
        case .gemini: AppText.ui("Gemini 音轨识别 · 云端", "Gemini audio recognition · Cloud", "Gemini 音声認識・クラウド")
        case .nemotron: AppText.ui("Nemotron 音轨识别 · 本地", "Nemotron audio · On-device", "Nemotron 音声認識・端末内")
        case .imported: AppText.ui("导入 SRT／VTT", "Import SRT / VTT", "SRT／VTT を読み込む")
        }
    }
}
enum VideoSubtitleTranslator: String, CaseIterable, Identifiable {
    case index, openAI, cloudflare
    var id: String { rawValue }
    var title: String { self == .cloudflare ? CloudflareCopy.title : self == .index ? AppText.ui("Index 在线翻译", "Index translation", "Index オンライン翻訳") : "OpenAI · GPT-4.1 mini" }
}

@Observable @MainActor
final class VideoSubtitlePreloadStore {
    var videoURL = ""
    var sourceLanguage = LanguageOption.supported.first { $0.id == "ja-JP" }!
    private(set) var automaticallySelectsSourceLanguageFromTitle = true
    private(set) var detectedVideoTitle = ""
    private(set) var titleLanguageSuggestion: LanguageOption?
    @ObservationIgnored private var titleVideoID: String?
    var titleLanguageStatus: String {
        if !automaticallySelectsSourceLanguageFromTitle {
            return AppText.ui("已手动选择原文语言；重新勾选可恢复标题推测。", "Original language selected manually. Re-enable this option to use title hints.", "原文言語を手動で選択しました。再度オンにするとタイトルから推測します。")
        }
        guard titleVideoID == (try? YouTubeVideoReference(videoURL))?.id, !detectedVideoTitle.isEmpty else {
            return AppText.ui("读取视频标题后推测原文语言，可手动更改。", "The video title suggests the original language. You can change it manually.", "動画タイトルから原文言語を推測します。手動でも変更できます。")
        }
        if let language = titleLanguageSuggestion {
            return AppText.ui("按标题推测：\(language.localizedTitle)。标题可能与实际语音不同，可手动更改。", "Title hint: \(language.localizedTitle). The spoken language may differ; you can change it manually.", "タイトルからの推測：\(language.localizedTitle)。実際の音声と異なる場合は手動で変更できます。")
        }
        return AppText.ui("标题语言不明确或暂不支持，保留当前原文语言。", "The title language is unclear or unsupported. Keeping the current original language.", "タイトルの言語が不明確または未対応のため、現在の原文言語を維持します。")
    }
    var targetLanguage = LanguageOption.supported.first { $0.id == "zh-CN" }!
    var input = VideoSubtitleInput.youtube
    var translator = VideoSubtitleTranslator.index
    var browser = VideoPlaybackBrowser.chrome
    var automaticallyReadsBrowserTab = true
    private var browserTabStatusText = MediaLocalizedText("正在读取当前标签页…", "Reading the current tab…", "現在のタブを読み取り中…")
    private(set) var browserTabNeedsAttention = false
    var browserTabStatus: String {
        if !automaticallyReadsBrowserTab {
            return AppText.ui("自动读取已关闭，可手动输入视频链接。", "Automatic reading is off. You can enter a video link manually.", "自動読み取りはオフです。動画リンクを手動で入力できます。")
        }
        if isConfigurationLocked {
            return AppText.ui("已固定当前视频，停止后继续自动读取。", "The current video is locked. Automatic reading resumes after stopping.", "現在の動画を固定しています。停止後に自動読み取りを再開します。")
        }
        return browserTabStatusText.value
    }
    private var statusText = MediaLocalizedText("输入 YouTube 链接，先准备字幕，再连接浏览器播放。", "Enter a YouTube link, prepare captions, then connect your browser.", "YouTube リンクを入力し、字幕を準備してからブラウザに接続してください。")
    var status: String { statusText.value }
    var connectionStatus: String { connectionStatusText.value }
    var error: String?
    var isPreparing = false
    var progress = 0.0
    var document: VideoSubtitleDocument?
    var isConnected = false
    var isConnecting = false
    private var connectionStatusText = MediaLocalizedText("未连接浏览器", "Browser not connected", "ブラウザ未接続")
    var activeCue: VideoSubtitleCue?
    var playbackTime = 0.0
    private var connectedVideoID: String?
    private(set) var isChangingPlayback = false
    var isPaused = true
    var isAd = false
    var timingOffset = 0.0
    var showsTranslation = true
    @ObservationIgnored weak var captionSession: TranslationSessionStore?
    var overlayVisible = false
    @ObservationIgnored private var imported: [VideoSubtitleCue] = []
    @ObservationIgnored private var importedHash = ""
    @ObservationIgnored private var preparation: Task<Void, Never>?
    @ObservationIgnored private var monitoring: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var connectionGeneration = UUID()
    @ObservationIgnored let cache: VideoSubtitleCache
    @ObservationIgnored private let connection: any VideoPlaybackReading
    @ObservationIgnored private let browserTabs: any VideoBrowserTabReading
    @ObservationIgnored private let audio = VideoAudioTranscription()
    @ObservationIgnored private let openAI = OpenAITranslationService()
    @ObservationIgnored private var overlay: VideoSubtitleOverlayController?

    init(connection: any VideoPlaybackReading = VideoBrowserConnection(), cache: VideoSubtitleCache = VideoSubtitleCache(),
         browserTabs: any VideoBrowserTabReading = VideoBrowserConnection()) {
        self.connection = connection
        self.cache = cache
        self.browserTabs = browserTabs
    }

    func setVideoURLManually(_ value: String) {
        guard !isConfigurationLocked else { return }
        automaticallyReadsBrowserTab = false
        videoURL = value
    }

    func setSourceLanguageManually(_ language: LanguageOption) {
        guard !isConfigurationLocked else { return }
        automaticallySelectsSourceLanguageFromTitle = false
        sourceLanguage = language
    }

    func setTitleLanguageSelectionEnabled(_ enabled: Bool) {
        guard !isConfigurationLocked else { return }
        automaticallySelectsSourceLanguageFromTitle = enabled
        if enabled, titleVideoID == (try? YouTubeVideoReference(videoURL))?.id,
           let language = titleLanguageSuggestion { sourceLanguage = language }
    }

    private func updateVideoTitle(_ title: String, video: YouTubeVideoReference) {
        let boundedTitle = String(title.prefix(512))
        if titleVideoID != video.id || detectedVideoTitle != boundedTitle {
            titleVideoID = video.id
            detectedVideoTitle = boundedTitle
            titleLanguageSuggestion = VideoTitleLanguage.infer(from: boundedTitle)
        }
        if automaticallySelectsSourceLanguageFromTitle, let language = titleLanguageSuggestion {
            sourceLanguage = language
        }
    }

    /// The view owns this task, so leaving Media or changing browsers cancels discovery.
    func monitorCurrentBrowserTab() async {
        guard automaticallyReadsBrowserTab else { return }
        browserTabNeedsAttention = false
        browserTabStatusText = MediaLocalizedText("正在读取当前标签页…", "Reading the current tab…", "現在のタブを読み取り中…")
        while !Task.isCancelled, automaticallyReadsBrowserTab {
            guard await refreshCurrentBrowserTab() else { return }
            do { try await Task.sleep(for: .seconds(1)) }
            catch { return }
        }
    }

    /// Return false for permission failures so a denied Automation prompt is not repeated.
    @discardableResult
    func refreshCurrentBrowserTab() async -> Bool {
        guard automaticallyReadsBrowserTab, !isConfigurationLocked, !Task.isCancelled else { return true }
        let selectedBrowser = browser, originalURL = videoURL
        let connectionToken = connectionGeneration, preparationToken = generation
        func requestIsCurrent() -> Bool {
            !Task.isCancelled && automaticallyReadsBrowserTab && !isConfigurationLocked
                && browser == selectedBrowser && videoURL == originalURL
                && connectionGeneration == connectionToken && generation == preparationToken
        }
        do {
            let tab = try await browserTabs.currentVideoTab(selectedBrowser)
            guard requestIsCurrent() else { return true }
            browserTabNeedsAttention = false
            if let tab, let video = try? YouTubeVideoReference(tab.url) {
                videoURL = video.url.absoluteString
                updateVideoTitle(tab.title, video: video)
                browserTabStatusText = MediaLocalizedText("已读取当前 YouTube 视频链接。", "The current YouTube video link has been filled in.", "現在の YouTube 動画リンクを入力しました。")
            } else {
                browserTabStatusText = MediaLocalizedText("请在 \(selectedBrowser.title) 的当前标签页打开 YouTube 视频，也可手动输入链接。", "Open a YouTube video in the current \(selectedBrowser.title) tab, or enter a link manually.", "\(selectedBrowser.title) の現在のタブで YouTube 動画を開くか、リンクを手動で入力してください。")
            }
            return true
        } catch {
            guard requestIsCurrent() else { return true }
            browserTabNeedsAttention = true
            browserTabStatusText = MediaLocalizedText(verbatim: Self.message(for: error))
            return (error as? VideoPlaybackReadError)?.canRetry ?? false
        }
    }

    var translatedCount: Int { document?.cues.filter { !$0.translation.isEmpty }.count ?? 0 }
    private var inputKey: String { input == .imported ? "import:" + importedHash : input.rawValue }
    var cacheSelectionKey: String {
        [(try? YouTubeVideoReference(videoURL))?.id ?? "", sourceLanguage.id, targetLanguage.id,
         translationCacheProvider, inputKey].joined(separator: "\u{0}")
    }
    var cloudflareConfiguration: CloudflareConfiguration { captionSession?.localTranslation.cloudflareConfiguration ?? .init() }
    private var translationCacheProvider: String {
        translator == .cloudflare ? cloudflareConfiguration.cacheIdentity : translator.rawValue
    }
    private var hasMatchingDocument: Bool {
        guard let document, let video = try? YouTubeVideoReference(videoURL) else { return false }
        return document.videoID == video.id && document.sourceLanguage == sourceLanguage.id
            && document.targetLanguage == targetLanguage.id && document.provider == translationCacheProvider
            && document.input == inputKey
    }
    var prepareTitle: String {
        guard hasMatchingDocument else { return AppText.ui("开始预加载", "Prepare captions", "字幕を準備") }
        if document?.completed == true { return AppText.ui("已从本机载入", "Loaded from cache", "キャッシュ読込済み") }
        return document?.audioProgress?.isRecognitionComplete == false ? AppText.ui("继续准备字幕", "Continue preparation", "準備を再開") : AppText.ui("补齐缺失字幕", "Complete captions", "未完了の字幕を補完")
    }
    var readyThroughTime: Double {
        document?.cues.prefix(while: { !$0.translation.isEmpty }).last?.end ?? 0
    }
    var preparationSummary: String {
        guard let document else { return "" }
        if let audio = document.audioProgress, !audio.isRecognitionComplete {
            return AppText.ui("\(translatedCount) 段已准备 · 识别 \(audio.nextRange) / \(audio.ranges.count)", "\(translatedCount) captions ready · Recognition \(audio.nextRange) / \(audio.ranges.count)", "\(translatedCount) 件準備済み・認識 \(audio.nextRange) / \(audio.ranges.count)")
        }
        return AppText.ui("\(translatedCount) / \(document.cues.count) 段已准备", "\(translatedCount) / \(document.cues.count) captions ready", "\(translatedCount) / \(document.cues.count) 件準備済み")
    }
    var isConfigurationLocked: Bool { isPreparing || isConnected || isConnecting }
    var showsImportAction: Bool { input == .imported }
    var showsGeminiConfiguration: Bool { input == .gemini }
    var showsOpenAIConfiguration: Bool { input == .openAI || translator == .openAI }

    /// Keep reading context on the main window during pauses and gaps between cues.
    /// Floating subtitles still use activeCue so expired text is not overlaid on video.
    var mainCaptionCue: VideoSubtitleCue? {
        if let activeCue { return activeCue }
        guard isConnected, !isAd, let document, connectedVideoID == document.videoID else { return nil }
        return VideoSubtitleTimeline.mostRecentCue(in: document.cues, at: playbackTime - timingOffset)
    }

    var visibleCaptionContext: [VideoSubtitleCue] {
        guard let activeCue = mainCaptionCue else { return [] }
        guard let cues = document?.cues,
              let index = cues.firstIndex(where: { $0.id == activeCue.id }) else { return [activeCue] }
        return Array(cues[max(0, index - 1)..<min(cues.count, index + 2)])
    }

    var mainActionTitle: String {
        if isPreparing { return AppText.ui("停止准备", "Stop preparation", "準備を停止") }
        if isConnected { return AppText.ui("停止同步", "Stop sync", "同期を停止") }
        if isConnecting { return AppText.ui("停止连接", "Cancel connection", "接続を中止") }
        if document != nil { return AppText.ui("连接视频", "Connect video", "動画に接続") }
        return AppText.ui("开始预加载", "Prepare captions", "字幕を準備")
    }
    var canPerformMainAction: Bool { isPreparing || isConnected || isConnecting || document != nil || canPrepare }
    func performMainAction() {
        if isPreparing { cancel() }
        else if isConnected || isConnecting { disconnect() }
        else if document != nil { connect(prepareCaptions: true) }
        else { prepare() }
    }

    var canPrepare: Bool { canStartPreparation(whileConnected: false) }

    private func canStartPreparation(whileConnected: Bool) -> Bool {
        !isPreparing && (!isConfigurationLocked || (whileConnected && isConnected && !isConnecting)) && (try? YouTubeVideoReference(videoURL)) != nil
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
            statusText = MediaLocalizedText("输入 YouTube 链接，先准备字幕，再连接浏览器播放。", "Enter a YouTube link, prepare captions, then connect your browser.", "YouTube リンクを入力し、字幕を準備してからブラウザに接続してください。"); return
        }
        let source = sourceLanguage.id, target = targetLanguage.id, provider = translationCacheProvider, selectedInput = inputKey
        do {
            let saved = try await cache.load(videoID: video.id, source: source, target: target,
                                             provider: provider, input: selectedInput)
            guard !Task.isCancelled, !isPreparing, cacheSelectionKey == selection else { return }
            guard let saved else {
                statusText = MediaLocalizedText("未找到匹配的本机缓存，可开始预加载。", "No matching cache found. You can prepare captions.", "一致するキャッシュがありません。字幕を準備できます。"); return
            }
            document = saved
            progress = Double(translatedCount) / Double(max(1, saved.cues.count))
            if saved.completed {
                statusText = MediaLocalizedText("已自动载入本机缓存，无需重新下载或翻译。可直接连接浏览器显示字幕。", "Cached captions loaded. Connect your browser to use them without downloading or translating again.", "キャッシュを読み込みました。再ダウンロードや再翻訳せず、ブラウザに接続して字幕を表示できます。")
            } else if saved.audioProgress?.isRecognitionComplete == false {
                statusText = MediaLocalizedText("已自动载入本机缓存，可直接播放已准备的字幕；点击“继续准备字幕”从未完成片段继续。", "Cache loaded. Ready captions are available; choose Continue preparation to resume unfinished audio segments.", "キャッシュを読み込みました。準備済みの字幕を再生できます。「準備を再開」で未完了の音声区間から続行します。")
            } else {
                statusText = MediaLocalizedText("已自动载入本机缓存，已准备的字幕可直接播放；点击“补齐缺失字幕”只处理未完成部分。", "Cache loaded. Ready captions are available; choose Complete captions to process only unfinished translations.", "キャッシュを読み込みました。準備済みの字幕を再生できます。「未完了の字幕を補完」で残りの翻訳だけを処理します。")
            }
            refreshCue()
        } catch {
            guard !Task.isCancelled, !isPreparing, cacheSelectionKey == selection else { return }
            statusText = MediaLocalizedText("本机缓存无法读取，可重新预加载。", "The local cache could not be read. Prepare captions again.", "キャッシュを読み込めませんでした。字幕を再度準備してください。")
        }
    }

    func prepare() { prepare(whileConnected: false) }

    private func prepare(whileConnected: Bool) {
        guard canStartPreparation(whileConnected: whileConnected), let video = try? YouTubeVideoReference(videoURL) else { return }
        error = nil; isPreparing = true; progress = 0; activeCue = nil; document = nil
        let source = sourceLanguage, target = targetLanguage, provider = translator, selectedInput = input
        let inputKey = selectedInput == .imported ? "import:" + importedHash : selectedInput.rawValue
        let providerKey = translationCacheProvider
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
                                                    provider: providerKey, input: inputKey) {
                    document = saved
                    if saved.completed { progress = 1; statusText = MediaLocalizedText("已读取本机缓存，可连接浏览器显示字幕。", "Cache loaded. Connect your browser to show captions.", "キャッシュを読み込みました。ブラウザに接続して字幕を表示できます。"); refreshCue(); return }
                }
                if provider == .cloudflare {
                    _ = try cloudflareConfiguration.validated()
                    guard captionSession?.hasCloudflareAPIKey == true else { throw CloudflareTranslationError.missingKey }
                }
                if selectedInput == .openAI || provider == .openAI {
                    let key = try await Task.detached { try OpenAIAPIKeyStore.readAPIKey(retryAfterFailure: true) }.value
                    guard key?.isEmpty == false else { throw VideoPreloadProblem(message: AppText.ui("请先在设置 → API 密钥中配置 OpenAI。", "Configure OpenAI in Settings → API Keys first.", "先に「設定 → API キー」で OpenAI を設定してください。")) }
                }
                try Task.checkCancellation()
                if selectedInput.requiresAudioRecognition && (document == nil || document?.audioProgress?.isRecognitionComplete == false) {
                    if selectedInput == .nemotron { try NemotronVideoRecognizer.validate() }
                    let geminiKey = selectedInput == .gemini
                        ? try await Task.detached { try GeminiAPIKeyStore.readAPIKey() }.value : nil
                    if selectedInput == .gemini, geminiKey?.isEmpty != false {
                        throw VideoPreloadProblem(message: AppText.ui("请先在设置 → API 密钥中配置 Gemini。", "Configure Gemini in Settings → API Keys first.", "先に「設定 → API キー」で Gemini を設定してください。"))
                    }
                    // Finish a cached phrase whose recognition succeeded but translation was interrupted.
                    try await translatePending(source: source, target: target, provider: provider, token: token)
                    statusText = MediaLocalizedText("正在获取视频音轨…已有字幕可先播放。", "Fetching video audio… Ready captions can already be played.", "動画の音声を取得中…準備済みの字幕は再生できます。")
                    let result = try await VideoMediaTools.shared.audio(for: video, directory: folder)
                    if document == nil {
                        statusText = MediaLocalizedText("正在划分音轨片段，随后边识别边翻译…", "Segmenting audio, then recognizing and translating each phrase…", "音声を区切り、区間ごとに認識と翻訳を進めます…")
                        let ranges = try await audio.prepareRanges(result.url)
                        document = .init(videoID: video.id, title: result.title, sourceLanguage: source.id,
                            targetLanguage: target.id, provider: providerKey, input: inputKey, cues: [],
                            audioProgress: .init(ranges: ranges))
                        if let document { try await cache.save(document) }
                    }
                    guard let checkpoint = document?.audioProgress else { throw VideoSubtitleError.invalidAudio }
                    try await audio.transcribe(result.url, language: source, ranges: checkpoint.ranges,
                                               from: checkpoint.nextRange, engine: selectedInput.audioEngine, geminiAPIKey: geminiKey) { [weak self] cue, done, total in
                        guard let self, self.generation == token else { throw CancellationError() }
                        try Task.checkCancellation()
                        if let cue { self.document?.cues.append(cue) }
                        self.document?.audioProgress?.nextRange = done
                        self.document?.updatedAt = Date()
                        // Persist recognition before translating: a failed translation must not resend audio.
                        if let document = self.document { try await self.cache.save(document) }
                        self.statusText = MediaLocalizedText("识别音轨 \(done) / \(total)，正在准备本段译文…", "Audio recognition \(done) / \(total). Translating this phrase…", "音声認識 \(done) / \(total)。この区間を翻訳中…")
                        if cue != nil, let index = self.document?.cues.indices.last {
                            try await self.translateCue(at: index, source: source, target: target, provider: provider, token: token)
                        }
                        self.progress = Double(done) / Double(max(1, total))
                        self.statusText = MediaLocalizedText("已准备至 \(Self.timestamp(self.readyThroughTime))，可先播放；后续字幕继续处理中（\(done) / \(total)）。", "Ready through \(Self.timestamp(self.readyThroughTime)). Playback is available; preparing remaining captions (\(done) / \(total)).", "\(Self.timestamp(self.readyThroughTime)) まで準備済み。再生しながら残りの字幕を準備できます（\(done) / \(total)）。")
                        self.refreshCue()
                    }
                    guard self.document?.cues.isEmpty == false else {
                        throw VideoPreloadProblem(message: AppText.ui("音轨中未识别到可用语音。", "No usable speech was recognized in the audio.", "音声から認識できる発話が見つかりませんでした。"))
                    }
                    document?.completed = true
                    if let document { try await cache.save(document) }
                    statusText = MediaLocalizedText("字幕已准备完成，重播时可直接使用本机缓存。", "Captions are ready. Replay using the local cache.", "字幕の準備が完了しました。次回はキャッシュを利用できます。"); progress = 1
                    return
                }
                if document == nil {
                    let title: String, cues: [VideoSubtitleCue]
                    switch selectedInput {
                    case .youtube:
                        statusText = MediaLocalizedText("正在准备视频组件并获取原文字幕…首次需要下载组件。", "Preparing video tools and fetching source captions… Tools must be downloaded on first use.", "動画ツールを準備し、原文字幕を取得中…初回はツールのダウンロードが必要です。")
                        let result = try await VideoMediaTools.shared.subtitles(for: video, language: String(source.id.prefix(2)), directory: folder)
                        title = result.title; cues = result.cues
                    case .imported:
                        title = video.id; cues = importedCues
                    case .openAI, .gemini, .nemotron:
                        throw VideoSubtitleError.invalidAudio
                    }
                    guard !cues.isEmpty, cues.count <= 30_000, (cues.last?.end ?? 0) <= 43_200 else {
                        throw VideoPreloadProblem(message: AppText.ui("字幕为空或视频过长，暂无法预加载。", "Captions are empty or the video is too long to preload.", "字幕が空か、動画が長すぎるため準備できません。"))
                    }
                    document = .init(videoID: video.id, title: title, sourceLanguage: source.id,
                        targetLanguage: target.id, provider: providerKey, input: inputKey, cues: Self.group(cues))
                    if let document { try await cache.save(document) }
                }
                guard document?.cues.isEmpty == false else { throw VideoSubtitleError.noSubtitles }
                try await translatePending(source: source, target: target, provider: provider, token: token)
                document?.completed = true
                if let document { try await cache.save(document) }
                statusText = MediaLocalizedText("字幕已准备完成，重播时可直接使用本机缓存。", "Captions are ready. Replay using the local cache.", "字幕の準備が完了しました。次回はキャッシュを利用できます。"); progress = 1
            } catch {
                if let document { try? await cache.save(document) }
                guard generation == token else { return }
                if Task.isCancelled || error is CancellationError { statusText = MediaLocalizedText("已停止准备，已完成的字幕保留在本机。", "Preparation stopped. Completed captions remain cached.", "準備を停止しました。完了した字幕はキャッシュに保存されています。") }
                else {
                    self.error = Self.message(for: error)
                    statusText = MediaLocalizedText("准备未完成；可重试，已完成的译文会复用。", "Preparation is incomplete. Retry to reuse completed translations.", "準備は未完了です。再試行時には完了済みの翻訳を再利用します。")
                }
            }
        }
    }

    private func translatePending(source: LanguageOption, target: LanguageOption,
                                  provider: VideoSubtitleTranslator, token: UUID) async throws {
        let total = document?.cues.count ?? 0
        for index in 0..<total {
            statusText = MediaLocalizedText("正在准备译文 \(index + 1) / \(total)，已完成的字幕可先播放。", "Translating \(index + 1) / \(total). Ready captions can already be played.", "翻訳中 \(index + 1) / \(total)。完了した字幕は再生できます。")
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
        else if provider == .cloudflare {
            let configuration = cloudflareConfiguration
            let key = try await Task.detached { try CloudflareAPIKeyStore.readAPIKey() }.value
            translated = try await CloudflareTranslationService.shared.translate(cue.source, source: source.id,
                target: target.id, configuration: configuration, key: key)
        } else if provider == .openAI {
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
            input = .imported; error = nil; statusText = MediaLocalizedText("已导入 \(file.lastPathComponent)，共 \(imported.count) 段。", "Imported \(file.lastPathComponent): \(imported.count) captions.", "\(file.lastPathComponent) を読み込みました（\(imported.count) 件）。")
        } catch { self.error = Self.message(for: error) }
    }

    func connect(prepareCaptions: Bool = false) {
        disconnect()
        let token = UUID(); connectionGeneration = token
        let selectedBrowser = browser
        isConnecting = true
        connectionStatusText = MediaLocalizedText("正在连接 \(selectedBrowser.title)…", "Connecting to \(selectedBrowser.title)…", "\(selectedBrowser.title) に接続中…")
        monitoring = Task {
            var initial = true
            var needsPreparation = prepareCaptions
            while !Task.isCancelled {
                do {
                    let snapshot = try await connection.read(selectedBrowser, initial: initial, videoID: needsPreparation ? nil : document?.videoID ?? connectedVideoID)
                    guard connectionGeneration == token, !Task.isCancelled else { return }
                    let shouldPrepare = needsPreparation
                    needsPreparation = false
                    initial = false
                    isConnecting = false
                    let currentVideo = try YouTubeVideoReference(snapshot.url ?? "")
                    if shouldPrepare {
                        videoURL = currentVideo.url.absoluteString
                        if !isPreparing { updateVideoTitle(snapshot.title ?? "", video: currentVideo) }
                        if !hasMatchingDocument { document = nil; activeCue = nil }
                    } else if videoURL.isEmpty { videoURL = currentVideo.url.absoluteString }
                    connectedVideoID = currentVideo.id
                    isConnected = true; playbackTime = snapshot.time ?? 0
                    isPaused = snapshot.paused ?? true; isAd = snapshot.ad ?? false
                    if let document, currentVideo.id != document.videoID {
                        activeCue = nil; connectionStatusText = MediaLocalizedText("当前视频与已准备的字幕不同，请切回原视频。", "This video does not match the prepared captions. Return to the original video.", "準備した字幕と動画が一致しません。元の動画に戻ってください。")
                    } else {
                        connectionStatusText = isAd ? MediaLocalizedText("广告播放中，字幕暂时隐藏", "Ad playing; captions hidden temporarily", "広告の再生中は字幕を非表示にします") : isPaused ? MediaLocalizedText("已同步 · 已暂停", "Synced · Paused", "同期済み・一時停止中") : MediaLocalizedText("已同步 · \(snapshot.rate ?? 1)×", "Synced · \(snapshot.rate ?? 1)×", "同期済み・\(snapshot.rate ?? 1) 倍速")
                        refreshCue()
                    }
                    if shouldPrepare { prepare(whileConnected: true) }
                    try await Task.sleep(for: .milliseconds(250))
                } catch {
                    guard connectionGeneration == token, !Task.isCancelled else { return }
                    if let readError = error as? VideoPlaybackReadError, readError.canRetry {
                        initial = false
                        connectionStatusText = MediaLocalizedText("视频窗口切换中，正在恢复原视频同步…", "Restoring video sync after a window change…", "動画ウィンドウの切り替え後、元の動画との同期を復旧中…")
                        do { try await Task.sleep(for: .milliseconds(500)) }
                        catch { return }
                        continue
                    }
                    connectionStatusText = MediaLocalizedText(verbatim: Self.message(for: error))
                    isConnecting = false; isConnected = false; activeCue = nil; return
                }
            }
        }
    }
    var canTogglePlayback: Bool { isConnected && !isChangingPlayback && connectedVideoID != nil }

    func togglePlayback() async {
        guard canTogglePlayback, let videoID = connectedVideoID else { return }
        let token = connectionGeneration
        let paused = !isPaused
        isChangingPlayback = true
        defer { if connectionGeneration == token { isChangingPlayback = false } }
        do {
            let snapshot = try await connection.setPaused(paused, browser: browser, videoID: videoID)
            guard connectionGeneration == token, isConnected else { return }
            isPaused = snapshot.paused ?? isPaused
            playbackTime = snapshot.time ?? playbackTime
            refreshCue()
        } catch {
            guard connectionGeneration == token, isConnected else { return }
            self.error = error.localizedDescription
        }
    }

    func disconnect() {
        isChangingPlayback = false
        connectionGeneration = UUID(); monitoring?.cancel(); monitoring = nil
        isConnecting = false; isConnected = false; connectedVideoID = nil; activeCue = nil; connectionStatusText = MediaLocalizedText("未连接浏览器", "Browser not connected", "ブラウザ未接続")
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
        do { try Self.exportSRT(document) }
        catch { self.error = AppText.subtitleExportFailed }
    }

    static func exportSRT(_ document: VideoSubtitleDocument) throws {
        let text = VideoSubtitleTimeline.srt(document.cues)
        guard !text.isEmpty else { throw VideoSubtitleError.noSubtitles }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Wenyi-\(document.videoID)-\(document.targetLanguage).srt"
        if let srtType = UTType(filenameExtension: "srt") {
            panel.allowedContentTypes = [srtType]
        }
        guard panel.runModal() == .OK, let file = panel.url else { return }
        try text.write(to: file, atomically: true, encoding: .utf8)
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
        if error is VideoSubtitleError { return AppText.ui("无法读取视频或字幕，请检查 YouTube 链接及 SRT／VTT 文件。", "Cannot read the video or captions. Check the YouTube link and SRT / VTT file.", "動画または字幕を読み込めません。YouTube リンクと SRT／VTT ファイルを確認してください。") }
        return error.localizedDescription
    }
}
