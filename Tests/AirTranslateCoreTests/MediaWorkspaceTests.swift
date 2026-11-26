import AVFoundation
import AppKit
import SwiftUI
import Foundation
import Testing
import AirTranslateCore
@testable import AirTranslate

@Suite(.serialized)
@MainActor
struct MediaWorkspaceTests {
    @Test(arguments: [
        ("How to understand the world through stories and everyday conversations - YouTube", "en-US"),
        ("これからの社会で私たちはどのように暮らしていけばよいのでしょうか - YouTube", "ja-JP"),
        ("우리는 앞으로 어떻게 살아가야 하는지 함께 이야기해 봅니다", "ko-KR"),
        ("我们如何在不断变化的世界中寻找生活的意义和方向", "zh-CN"),
        ("Cómo podemos comprender mejor el mundo y aprender de nuestras experiencias", "es-ES"),
        ("Comment comprendre le monde qui nous entoure et apprendre de nos expériences", "fr-FR"),
        ("Wie können wir die Welt besser verstehen und aus unseren Erfahrungen lernen", "de-DE")
    ])
    func titleLanguageRecognizesClearSupportedTitles(example: (String, String)) {
        #expect(VideoTitleLanguage.infer(from: example.0)?.id == example.1)
    }

    @Test(arguments: ["", "YouTube", "2026 🔥", "AI", "Christopher Nolan", "Episode 12",
        "English conversation 日本語の会話", "Как лучше понять окружающий нас мир и научиться жить вместе"])
    func uncertainAndUnsupportedTitlesDoNotForceALanguage(title: String) {
        #expect(VideoTitleLanguage.infer(from: title) == nil)
    }

    @Test func titleHintSelectsOriginalLanguageBeforeRestoringTheMatchingCache() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = VideoSubtitleCache(root: folder)
        try await cache.save(.init(videoID: "PMGSdzyRZUw", title: "Cached video", sourceLanguage: "en-US",
            targetLanguage: "zh-CN", provider: "index", input: "youtube",
            cues: [.init(id: 0, start: 0, end: 3, source: "Cached source", translation: "Cached translation")], completed: true))
        let model = VideoSubtitlePreloadStore(cache: cache, browserTabs: ScriptedBrowserTabReader(
            url: "https://www.youtube.com/watch?v=PMGSdzyRZUw", title: "How to understand the world through stories and everyday conversations"))
        await model.refreshCurrentBrowserTab()
        await model.restoreCachedSelection()
        #expect(model.sourceLanguage.id == "en-US")
        #expect(model.targetLanguage.id == "zh-CN")
        #expect(model.document?.sourceLanguage == "en-US")
        #expect(model.document?.completed == true)
        #expect(!model.isPreparing)
    }

    @Test func manualLanguageChoiceSurvivesTitleRefreshUntilExplicitlyReenabled() async {
        let tabs = ScriptedBrowserTabReader(url: "https://www.youtube.com/watch?v=PMGSdzyRZUw",
            title: "How to understand the world through stories and everyday conversations")
        let model = VideoSubtitlePreloadStore(browserTabs: tabs)
        let japanese = LanguageOption.supported.first { $0.id == "ja-JP" }!
        model.setSourceLanguageManually(japanese)
        await model.refreshCurrentBrowserTab()
        #expect(model.sourceLanguage == japanese)
        #expect(!model.automaticallySelectsSourceLanguageFromTitle)
        model.setTitleLanguageSelectionEnabled(true)
        #expect(model.sourceLanguage == .english)
        model.setVideoURLManually("https://www.youtube.com/watch?v=abcdefghijk")
        model.setSourceLanguageManually(japanese)
        model.setTitleLanguageSelectionEnabled(true)
        #expect(model.sourceLanguage == japanese)
    }

    @Test func firstConnectedTitleSelectsLanguageBeforeCachedPreparation() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = VideoSubtitleCache(root: folder)
        try await cache.save(.init(videoID: "PMGSdzyRZUw", title: "Cached video", sourceLanguage: "en-US",
            targetLanguage: "zh-CN", provider: "index", input: "youtube",
            cues: [.init(id: 0, start: 0, end: 10, source: "Cached source", translation: "Cached translation")], completed: true))
        let reader = ScriptedPlaybackReader(steps: [.snapshot(.init(
            url: "https://www.youtube.com/watch?v=PMGSdzyRZUw", time: 3, paused: true, rate: 1, ad: false, unsupported: false,
            title: "How to understand the world through stories and everyday conversations"))])
        let model = VideoSubtitlePreloadStore(connection: reader, cache: cache)
        model.connect(prepareCaptions: true)
        defer { model.disconnect(); model.cancel() }
        try await waitForPlayback { model.document?.completed == true && !model.isPreparing }
        #expect(model.sourceLanguage == .english)
        #expect(model.document?.sourceLanguage == "en-US")
        #expect(model.activeCue?.translation == "Cached translation")
    }

    @Test func lateTitleReadRespectsManualLanguageChoice() async throws {
        let tabs = ScriptedBrowserTabReader(url: "https://www.youtube.com/watch?v=PMGSdzyRZUw",
            title: "How to understand the world through stories and everyday conversations", holdResponse: true)
        let model = VideoSubtitlePreloadStore(browserTabs: tabs)
        let pending = Task { await model.refreshCurrentBrowserTab() }
        try await waitForTabRequest(tabs)
        model.setSourceLanguageManually(.korean)
        await tabs.release()
        await pending.value
        #expect(model.sourceLanguage == .korean)
        #expect(model.titleLanguageSuggestion == .english)
    }

    @Test func uncertainTitleKeepsExistingSourceAndLockedSelectionIgnoresManualChanges() async {
        let model = VideoSubtitlePreloadStore(browserTabs: ScriptedBrowserTabReader(
            url: "https://www.youtube.com/watch?v=PMGSdzyRZUw", title: "AI"))
        model.sourceLanguage = .korean
        await model.refreshCurrentBrowserTab()
        #expect(model.sourceLanguage == .korean)
        #expect(model.titleLanguageSuggestion == nil)
        model.isConnected = true
        model.setSourceLanguageManually(.english)
        model.setTitleLanguageSelectionEnabled(false)
        #expect(model.sourceLanguage == .korean)
        #expect(model.automaticallySelectsSourceLanguageFromTitle)
    }

    @Test func currentTabDiscoveryFillsVideoURLAndRestoresCacheWithoutStartingPreparation() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = VideoSubtitleCache(root: folder)
        try await cache.save(.init(videoID: "PMGSdzyRZUw", title: "Cached video", sourceLanguage: "ja-JP",
            targetLanguage: "zh-CN", provider: "index", input: "youtube",
            cues: [.init(id: 0, start: 0, end: 3, source: "Cached source", translation: "Cached translation")], completed: true))
        let tabs = ScriptedBrowserTabReader(url: "https://youtu.be/PMGSdzyRZUw?t=30")
        let model = VideoSubtitlePreloadStore(cache: cache, browserTabs: tabs)
        await model.refreshCurrentBrowserTab()
        await model.restoreCachedSelection()
        #expect(model.videoURL == "https://www.youtube.com/watch?v=PMGSdzyRZUw")
        #expect(model.document?.completed == true)
        #expect(model.document?.cues.first?.translation == "Cached translation")
        #expect(!model.isPreparing && !model.isConnecting && !model.isConnected)
        #expect(await tabs.requests == [.chrome])
    }

    @Test(arguments: ["preparing", "connecting", "playing", "paused"])
    func tabDiscoveryCannotReplaceAnActiveVideo(phase: String) async {
        let tabs = ScriptedBrowserTabReader(url: "https://www.youtube.com/watch?v=abcdefghijk")
        let model = VideoSubtitlePreloadStore(browserTabs: tabs)
        model.videoURL = "https://www.youtube.com/watch?v=PMGSdzyRZUw"
        model.isPreparing = phase == "preparing"
        model.isConnecting = phase == "connecting"
        model.isConnected = phase == "playing" || phase == "paused"
        model.isPaused = phase == "paused"
        await model.refreshCurrentBrowserTab()
        #expect(model.videoURL.contains("PMGSdzyRZUw"))
        #expect(await tabs.requests.isEmpty)
    }

    @Test(arguments: ["manual", "browser", "stopped"])
    func lateTabReadsCannotOverrideANewerSelection(change: String) async throws {
        let tabs = ScriptedBrowserTabReader(url: "https://www.youtube.com/watch?v=PMGSdzyRZUw", holdResponse: true)
        let model = VideoSubtitlePreloadStore(browserTabs: tabs)
        let pending = Task { await model.refreshCurrentBrowserTab() }
        try await waitForTabRequest(tabs)
        if change == "manual" { model.setVideoURLManually("https://www.youtube.com/watch?v=abcdefghijk") }
        if change == "browser" { model.browser = .safari }
        if change == "stopped" { model.disconnect() }
        let selectedURL = model.videoURL
        await tabs.release()
        await pending.value
        #expect(model.videoURL == selectedURL)
        if change == "manual" { #expect(!model.automaticallyReadsBrowserTab) }
    }

    @Test func permissionDenialEndsDiscoveryAndLeavingMediaDiscardsPendingReads() async throws {
        let denied = ScriptedBrowserTabReader(url: nil, failure: .configuration("Permission denied"))
        let blocked = VideoSubtitlePreloadStore(browserTabs: denied)
        await blocked.monitorCurrentBrowserTab()
        #expect(blocked.browserTabNeedsAttention)
        #expect(blocked.browserTabStatus == "Permission denied")
        #expect(await denied.requests.count == 1)

        let tabs = ScriptedBrowserTabReader(url: "https://www.youtube.com/watch?v=PMGSdzyRZUw", holdResponse: true)
        let model = VideoSubtitlePreloadStore(browserTabs: tabs)
        let monitoring = Task { await model.monitorCurrentBrowserTab() }
        try await waitForTabRequest(tabs)
        monitoring.cancel()
        await tabs.release()
        await monitoring.value
        #expect(model.videoURL.isEmpty)
        #expect(await tabs.requests.count == 1)
    }

    @Test(arguments: [nil, "https://example.com/watch?v=abcdefghijk", "https://youtube.com.evil.example/watch?v=abcdefghijk"] as [String?])
    func unrelatedTabsKeepTheSelectedVideoAndCachedCaptions(url: String?) async {
        let model = VideoSubtitlePreloadStore(browserTabs: ScriptedBrowserTabReader(url: url))
        model.videoURL = "https://www.youtube.com/watch?v=PMGSdzyRZUw"
        model.document = .init(videoID: "PMGSdzyRZUw", title: "Cached", sourceLanguage: "ja-JP", targetLanguage: "zh-CN",
            provider: "index", input: "youtube", cues: [.init(id: 0, start: 0, end: 3, source: "Retained")])
        await model.refreshCurrentBrowserTab()
        #expect(model.videoURL.contains("PMGSdzyRZUw"))
        #expect(model.document?.cues.first?.source == "Retained")
        model.automaticallyReadsBrowserTab = false
        await model.refreshCurrentBrowserTab()
        #expect(!model.isPreparing)
    }

    @Test func currentTabDiscoveryScriptsCompileWithoutJavaScriptAccess() {
        for browser in VideoPlaybackBrowser.allCases {
            let appPath = browser == .chrome ? "/Applications/Google Chrome.app" : "/Applications/Safari.app"
            let source = VideoBrowserConnection.currentTabScriptSource(browser)
                .replacingOccurrences(of: "tell application id \"\(browser.bundleID)\"", with: "tell application \"\(appPath)\"")
            #expect(!source.localizedCaseInsensitiveContains("javascript"))
            var details: NSDictionary?
            #expect(NSAppleScript(source: source)?.compileAndReturnError(&details) == true, "\(details?.description ?? "")")
        }
    }

    @Test func localNemotronUsesSeparateCacheAndOnlyTextTranslationCredentials() {
        let model = VideoSubtitlePreloadStore()
        model.videoURL = "https://www.youtube.com/watch?v=PMGSdzyRZUw"
        model.input = .openAI
        let cloudKey = model.cacheSelectionKey
        model.input = .nemotron
        #expect(model.input.requiresAudioRecognition)
        #expect(model.input.audioEngine == .nemotron)
        #expect(model.cacheSelectionKey != cloudKey)
        #expect(!model.showsImportAction)
        #expect(!model.showsOpenAIConfiguration)
        model.translator = .openAI
        #expect(model.showsOpenAIConfiguration)
    }

    @Test func geminiMediaUsesItsOwnAudioEngineAndCheckpointKey() {
        let model = VideoSubtitlePreloadStore()
        model.videoURL = "https://www.youtube.com/watch?v=PMGSdzyRZUw"
        model.input = .openAI
        let otherKey = model.cacheSelectionKey
        model.input = .gemini
        #expect(model.input.audioEngine == .gemini)
        #expect(model.input.requiresAudioRecognition)
        #expect(model.cacheSelectionKey != otherKey)
        #expect(model.showsGeminiConfiguration)
        #expect(!model.showsOpenAIConfiguration)
        #expect(!model.showsImportAction)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["WENYI_NEMOTRON_VIDEO_SMOKE"] == "1"))
    func localNemotronVideoSmoke() async throws {
        let environment = ProcessInfo.processInfo.environment
        let resources = URL(fileURLWithPath: try #require(environment["WENYI_NEMOTRON_RESOURCES"]))
        let file = URL(fileURLWithPath: try #require(environment["WENYI_NEMOTRON_FIXTURE"]))
        let duration = try await AVURLAsset(url: file).load(.duration).seconds
        var captions: [VideoSubtitleCue] = []
        try await VideoAudioTranscription().transcribe(file, language: .english,
            ranges: [.init(start: 0, end: min(duration, 15))], from: 0, engine: .nemotron,
            resources: resources) { cue, done, total in
                if let cue { captions.append(cue) }
                #expect(done == 1 && total == 1)
            }
        #expect(captions.count == 1)
        let cue = try #require(captions.first)
        #expect(cue.source.lowercased().contains("country"))
        #expect(cue.start == 0)
    }

    @Test func localizedMediaTextAndControlsFitEnglishAndJapanese() {
        let original = InterfaceLocalization.shared.preference
        defer { InterfaceLocalization.shared.preference = original }
        let model = VideoSubtitlePreloadStore()
        for language in [AppInterfaceLanguage.english, .japanese, .chineseSimplified] {
            InterfaceLocalization.shared.preference = language
            let metrics = ConsoleLayoutMetrics.current
            let font = NSFont.systemFont(ofSize: 14, weight: .medium)
            let inputWidth = MainInputSelection.allCases.reduce(CGFloat(0)) { $0 + ($1.title as NSString).size(withAttributes: [.font: font]).width + 24 }
            let outputWidth = [ConsoleLayoutMetrics.originalOnly, ConsoleLayoutMetrics.bilingual].reduce(CGFloat(0)) { $0 + ($1 as NSString).size(withAttributes: [.font: font]).width + 24 }
            #expect(inputWidth <= metrics.inputWidth)
            #expect(outputWidth <= metrics.outputWidth)
            #expect(model.status == AppText.ui("输入 YouTube 链接，先准备字幕，再连接浏览器播放。", "Enter a YouTube link, prepare captions, then connect your browser.", "YouTube リンクを入力し、字幕を準備してからブラウザに接続してください。"))
            #expect(model.connectionStatus == AppText.ui("未连接浏览器", "Browser not connected", "ブラウザ未接続"))
            if language == .english {
                #expect(VideoSubtitleInput.allCases.allSatisfy { item in !item.title.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) } })
                #expect(VideoSubtitleTranslator.index.title == "Index translation")
            }
            for browser in VideoPlaybackBrowser.allCases {
                let steps = BrowserSyncSetup.steps(for: browser)
                #expect(steps.count == 4)
                #expect(steps[1].detail.value.contains(browser.title))
                #expect(steps.allSatisfy { !$0.title.value.isEmpty && !$0.detail.value.isEmpty })
            }
        }
    }

    @Test(arguments: [false, true]) func connectCurrentVideoLoadsCompletedCacheWithoutCloudRequests(afterWindowTransition: Bool) async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = VideoSubtitleCache(root: folder)
        let id = "PMGSdzyRZUw"
        let saved = VideoSubtitleDocument(videoID: id, title: "Cached video", sourceLanguage: "ja-JP",
            targetLanguage: "zh-CN", provider: "index", input: "youtube", cues: [
                .init(id: 0, start: 0, end: 10, source: "Cached source", translation: "缓存译文")])
        var completed = saved
        completed.completed = true
        try await cache.save(completed)
        var steps: [ScriptedPlaybackReader.Step] = []
        if afterWindowTransition { steps.append(.failure(.temporary("Window transition"))) }
        steps.append(.snapshot(.init(url: "https://www.youtube.com/watch?v=\(id)",
            time: 3, paused: true, rate: 1, ad: false, unsupported: false)))
        let reader = ScriptedPlaybackReader(steps: steps)
        let model = VideoSubtitlePreloadStore(connection: reader, cache: cache)
        model.videoURL = "https://www.youtube.com/watch?v=abcdefghijk"
        model.connect(prepareCaptions: true)
        defer { model.disconnect(); model.cancel() }
        try await waitForPlayback { model.document?.completed == true && !model.isPreparing }
        #expect(model.isConnected)
        #expect(model.activeCue?.translation == "缓存译文")
        #expect((try? YouTubeVideoReference(model.videoURL))?.id == id)
        #expect(model.error == nil)
        #expect(await reader.requests.first?.videoID == nil)
    }

    @Test func stoppingDuringReconnectCancelsFurtherReadsAndUnlocksSettings() async throws {
        let reader = ScriptedPlaybackReader(steps: [.failure(.temporary("Window transition"))])
        let model = VideoSubtitlePreloadStore(connection: reader)
        model.connect()
        try await waitForPlayback { model.connectionStatus.contains(AppText.ui("正在恢复", "Restoring", "復旧")) }
        #expect(model.isConnecting)
        #expect(model.isConfigurationLocked)
        model.performMainAction()
        #expect(!model.isConfigurationLocked)
        let stoppedCount = await reader.requests.count
        try await Task.sleep(for: .milliseconds(650))
        #expect(await reader.requests.count == stoppedCount)
        #expect(model.connectionStatus == AppText.ui("未连接浏览器", "Browser not connected", "ブラウザ未接続"))
    }

    @Test func fullscreenTransitionRecoversWithoutClearingCaptionsAndDisconnectCancelsRetry() async throws {
        let videoID = "PMGSdzyRZUw"
        let reader = ScriptedPlaybackReader(steps: [
            .snapshot(.init(url: "https://www.youtube.com/watch?v=\(videoID)", time: 3, paused: false, rate: 1, ad: false, unsupported: false)),
            .failure(.temporary("Window changed")),
            .snapshot(.init(url: "https://www.youtube.com/watch?v=\(videoID)", time: 9, paused: false, rate: 1, ad: false, unsupported: false))
        ])
        let model = VideoSubtitlePreloadStore(connection: reader)
        model.document = .init(videoID: videoID, title: "Fixture", sourceLanguage: "ja-JP", targetLanguage: "zh-CN", provider: "index", input: "youtube", cues: [
            .init(id: 0, start: 0, end: 5, source: "First", translation: "第一句"),
            .init(id: 1, start: 8, end: 12, source: "Next", translation: "下一句")])
        model.connect()
        try await waitForPlayback { model.connectionStatus.contains(AppText.ui("正在恢复", "Restoring", "復旧")) }
        #expect(model.isConnected)
        #expect(model.isConfigurationLocked)
        #expect(model.activeCue?.id == 0)
        #expect(!model.visibleCaptionContext.isEmpty)
        try await waitForPlayback { model.playbackTime == 9 }
        #expect(model.activeCue?.id == 1)
        let requests = await reader.requests
        #expect(requests.count >= 3)
        #expect(requests.allSatisfy { $0.videoID == videoID })
        #expect(requests[0].initial)
        #expect(!requests[1].initial)
        model.disconnect()
        let stoppedCount = await reader.requests.count
        try await Task.sleep(for: .milliseconds(300))
        #expect(await reader.requests.count == stoppedCount)
        #expect(!model.isConnected)
        #expect(!model.isConnecting)
    }

    @Test func permissionErrorsDoNotRetryOrKeepSettingsLocked() async throws {
        let reader = ScriptedPlaybackReader(steps: [.failure(.configuration("Permission denied"))])
        let model = VideoSubtitlePreloadStore(connection: reader)
        model.connect()
        #expect(model.isConfigurationLocked)
        try await waitForPlayback { model.connectionStatus == "Permission denied" }
        #expect(!model.isConfigurationLocked)
        try await Task.sleep(for: .milliseconds(300))
        #expect(await reader.requests.count == 1)
    }

    @Test func mediaPauseControlsLinkedVideoAndKeepsSyncLocked() async throws {
        let reader = ScriptedPlaybackReader(steps: [.snapshot(.init(url: "https://www.youtube.com/watch?v=PMGSdzyRZUw", time: 3, paused: false, rate: 1, ad: false, unsupported: false))])
        let model = VideoSubtitlePreloadStore(connection: reader)
        #expect(!model.canTogglePlayback)
        model.connect()
        try await waitForPlayback { model.isConnected }
        await model.togglePlayback()
        #expect(model.isPaused)
        #expect(model.isConfigurationLocked)
        #expect(await reader.controls.first?.videoID == "PMGSdzyRZUw")
        #expect(await reader.controls.first?.paused == true)
        await model.togglePlayback()
        #expect(!model.isPaused)
        #expect(await reader.controls.last?.paused == false)
        model.disconnect()
        await model.togglePlayback()
        #expect(await reader.controls.count == 2)
        #expect(!model.canTogglePlayback)
    }

    @Test func failedOrLatePlaybackCommandsDoNotDisconnectOrReviveSync() async throws {
        let reader = ScriptedPlaybackReader(steps: [.snapshot(.init(url: "https://www.youtube.com/watch?v=PMGSdzyRZUw", time: 3, paused: false, rate: 1, ad: false, unsupported: false))])
        let model = VideoSubtitlePreloadStore(connection: reader)
        model.connect()
        try await waitForPlayback { model.isConnected }
        await reader.setControlFailure(true)
        await model.togglePlayback()
        #expect(model.isConnected)
        #expect(model.error == "Playback rejected")
        #expect(!model.isChangingPlayback)
        await reader.setControlFailure(false)
        await reader.setControlDelay()
        let pending = Task { await model.togglePlayback() }
        try await waitForPlayback { model.isChangingPlayback }
        #expect(!model.canTogglePlayback)
        model.disconnect()
        await pending.value
        #expect(!model.isConnected)
        #expect(!model.isChangingPlayback)
        #expect(!model.isConfigurationLocked)
    }

    @Test func browserTrackingScriptsCompileForBothSupportedBrowsers() {
        for browser in VideoPlaybackBrowser.allCases {
            for initial in [true, false] {
              for paused in [nil, true, false] as [Bool?] {
                let appPath = browser == .chrome ? "/Applications/Google Chrome.app" : "/Applications/Safari.app"
                let source = VideoBrowserConnection.scriptSource(browser, initial: initial, videoID: "PMGSdzyRZUw", chromeTabID: 42, paused: paused)
                    .replacingOccurrences(of: "tell application id \"\(browser.bundleID)\"", with: "tell application \"\(appPath)\"")
                var details: NSDictionary?
                let script = NSAppleScript(source: source)
                #expect(script?.compileAndReturnError(&details) == true, "\(browser.title): \(details?.description ?? "")")
              }
            }
        }
    }

    @Test func mediaConfigurationStaysLockedUntilPreparationAndSyncStop() {
        let model = VideoSubtitlePreloadStore()
        model.videoURL = "https://www.youtube.com/watch?v=PMGSdzyRZUw"
        #expect(!model.isConfigurationLocked)
        #expect(model.canPrepare)
        model.isPreparing = true
        #expect(model.isConfigurationLocked)
        #expect(!model.canPrepare)
        model.isPreparing = false
        model.isConnected = true
        model.isPaused = false
        #expect(model.isConfigurationLocked)
        #expect(!model.canPrepare)
        model.isPaused = true
        #expect(model.isConfigurationLocked)
        model.disconnect()
        #expect(!model.isConfigurationLocked)
        #expect(model.canPrepare)
    }

    @Test func mainCaptionContextSurvivesSilentGapsWithoutExtendingOverlayTiming() {
        let cues = [VideoSubtitleCue(id: 0, start: 2, end: 4, source: "First", translation: "第一句"),
                    VideoSubtitleCue(id: 1, start: 8, end: 10, source: "Next", translation: "下一句")]
        #expect(VideoSubtitleTimeline.mostRecentCue(in: cues, at: 1) == nil)
        #expect(VideoSubtitleTimeline.mostRecentCue(in: cues, at: 6)?.id == 0)
        #expect(VideoSubtitleTimeline.activeCue(in: cues, at: 6) == nil)
        #expect(VideoSubtitleTimeline.mostRecentCue(in: cues, at: 8)?.id == 1)
        #expect(VideoSubtitleTimeline.mostRecentCue(in: cues, at: 12)?.id == 1)
        #expect(VideoSubtitleTimeline.mostRecentCue(in: cues, at: 3)?.id == 0)
        #expect(VideoSubtitleTimeline.mostRecentCue(in: cues, at: .nan) == nil)
    }

    @Test func captionColorsFollowSystemAppearance() throws {
        for (name, expectedSource, expectedBackground, expectedTranslation) in [
            (NSAppearance.Name.aqua, "#000000", "#F4F5F7", "#9A6700"),
            (NSAppearance.Name.darkAqua, "#FFFFFF", "#121417", "#FFD600")
        ] {
            let appearance = try #require(NSAppearance(named: name))
            appearance.performAsCurrentDrawingAppearance {
                #expect(FloatingCaptionAppearance.hexString(from: NSColor(AirTranslateDesign.Palette.captionSource)) == expectedSource)
                #expect(FloatingCaptionAppearance.hexString(from: NSColor(AirTranslateDesign.Palette.captionMediaCanvas)) == expectedBackground)
                #expect(FloatingCaptionAppearance.hexString(from: NSColor(AirTranslateDesign.Palette.captionTranslation)) == expectedTranslation)
                #expect(FloatingCaptionAppearance.hexString(from: NSColor(FloatingCaptionAppearance.translationTextColor)) == "#FFD600")
                #expect(FloatingCaptionAppearance.hexString(from: NSColor(FloatingCaptionAppearance.sourceTextColor)) == "#FFFFFF")
            }
        }
    }

    @Test func configurationActionsFollowSourceAndTranslator() {
        let model = VideoSubtitlePreloadStore()
        for source in VideoSubtitleInput.allCases {
            for translator in VideoSubtitleTranslator.allCases {
                model.input = source
                model.translator = translator
                #expect(model.showsImportAction == (source == .imported))
                #expect(model.showsOpenAIConfiguration == (source == .openAI || translator == .openAI))
                #expect(model.showsGeminiConfiguration == (source == .gemini))
            }
        }
    }

    @Test func mediaActionNeverNeedsAnAudioCaptureSession() {
        let model = VideoSubtitlePreloadStore()
        #expect(!model.canPerformMainAction)
        model.videoURL = "https://www.youtube.com/watch?v=PMGSdzyRZUw"
        #expect(model.canPerformMainAction)
        #expect(model.mainActionTitle == AppText.ui("开始预加载", "Prepare captions", "字幕を準備"))
        model.input = .imported
        #expect(!model.canPerformMainAction)
        model.isPreparing = true
        #expect(model.canPerformMainAction)
        #expect(model.mainActionTitle == "停止准备")
        model.isPreparing = false
        model.isConnected = true
        #expect(model.mainActionTitle == AppText.ui("停止同步", "Stop sync", "同期を停止"))
        model.performMainAction()
        #expect(!model.isConnected)
        #expect(model.activeCue == nil)
    }

    @Test func mediaOutputChoiceDoesNotChangeCachedTranslations() {
        let model = VideoSubtitlePreloadStore()
        model.document = .init(videoID: "PMGSdzyRZUw", title: "Fixture", sourceLanguage: "ja-JP", targetLanguage: "zh-CN", provider: "index", input: "youtube", cues: [.init(id: 0, start: 0, end: 3, source: "こんにちは", translation: "你好")], completed: true)
        model.activeCue = model.document?.cues.first
        #expect(model.mainActionTitle == AppText.ui("连接视频", "Connect video", "動画に接続"))
        model.showsTranslation = false
        #expect(model.document?.cues.first?.translation == "你好")
        #expect(model.activeCue?.source == "こんにちは")
        model.showsTranslation = true
        #expect(model.activeCue?.translation == "你好")
        #expect(MainInputSelection.allCases == [.systemAudio, .microphone, .media])
    }
    @Test func mediaContextTracksNeighbouringCuesAndTimelineEdges() {
        let model = VideoSubtitlePreloadStore()
        let cues = (0..<5).map { VideoSubtitleCue(id: $0, start: Double($0 * 3), end: Double($0 * 3 + 3), source: "Source \($0)", translation: "Translation \($0)") }
        model.document = .init(videoID: "fixture", title: "Fixture", sourceLanguage: "ja-JP", targetLanguage: "zh-CN", provider: "index", input: "youtube", cues: cues)
        #expect(model.visibleCaptionContext.isEmpty)
        model.activeCue = cues[2]
        #expect(model.visibleCaptionContext.map(\.id) == [1, 2, 3])
        model.activeCue = cues[0]
        #expect(model.visibleCaptionContext.map(\.id) == [0, 1])
        model.activeCue = cues[4]
        #expect(model.visibleCaptionContext.map(\.id) == [3, 4])
        model.activeCue = nil
        #expect(model.visibleCaptionContext.isEmpty)
    }

    @Test func inspectorPreservesSingleRowConsoleAtEveryAllowedWidth() {
        #expect(MediaWorkspaceLayout.sidebarWidth(for: 1640) == 480)
        #expect(MediaWorkspaceLayout.sidebarWidth(for: 900) == 300)
        #expect(900 - MediaWorkspaceLayout.sidebarWidth(for: 900) >= 600)
        #expect(MediaWorkspaceLayout.sidebarWidth(for: 2400) == 480)
        #expect(MediaWorkspaceLayout.expandedWindowWidth(from: 900, within: 1600) > 1200)
        #expect(MediaWorkspaceLayout.expandedWindowWidth(from: 900, within: 900) == MediaWorkspaceLayout.minimumExpandedWidth)
        #expect(MediaWorkspaceLayout.minimumWindowWidth(media: false) == MediaWorkspaceLayout.captionMinimumWidth)
        #expect(MediaWorkspaceLayout.minimumWindowWidth(media: true) == MediaWorkspaceLayout.minimumExpandedWidth)
        for width in stride(from: Double(MediaWorkspaceLayout.minimumExpandedWidth), through: 2400.0, by: 37) {
            let captionWidth = width - MediaWorkspaceLayout.sidebarWidth(for: width) - 1
            #expect(captionWidth >= MediaWorkspaceLayout.captionMinimumWidth)
        }
        #expect(MediaWorkspaceLayout.expandedWindowWidth(from: 1400, within: 1600) == 1600)
    }

}

@MainActor
private func waitForPlayback(_ condition: () -> Bool) async throws {
    for _ in 0..<200 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(condition(), "Playback state did not arrive")
}

private actor ScriptedBrowserTabReader: VideoBrowserTabReading {
    let url: String?
    let title: String
    let failure: VideoPlaybackReadError?
    var holdResponse: Bool
    private var pending: CheckedContinuation<Void, Never>?
    private(set) var requests: [VideoPlaybackBrowser] = []
    init(url: String?, title: String = "", failure: VideoPlaybackReadError? = nil, holdResponse: Bool = false) {
        self.url = url; self.title = title; self.failure = failure; self.holdResponse = holdResponse
    }
    func currentVideoTab(_ browser: VideoPlaybackBrowser) async throws -> VideoBrowserTabSnapshot? {
        requests.append(browser)
        if holdResponse { await withCheckedContinuation { pending = $0 } }
        if let failure { throw failure }
        return url.map { VideoBrowserTabSnapshot(url: $0, title: title) }
    }
    func release() { holdResponse = false; pending?.resume(); pending = nil }
}

private func waitForTabRequest(_ reader: ScriptedBrowserTabReader) async throws {
    for _ in 0..<200 {
        if await !reader.requests.isEmpty { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    throw VideoPlaybackReadError.temporary("Tab read did not start")
}

private actor ScriptedPlaybackReader: VideoPlaybackReading {
    enum Step: Sendable { case snapshot(VideoPlaybackSnapshot), failure(VideoPlaybackReadError) }
    struct Request: Sendable { let initial: Bool; let videoID: String? }
    struct Control: Sendable { let paused: Bool; let videoID: String }
    private(set) var controls: [Control] = []
    private var controlledPaused: Bool?
    private var controlFailure = false
    private var controlDelay = false
    func setControlFailure(_ enabled: Bool) { controlFailure = enabled }
    func setControlDelay() { controlDelay = true }
    func setPaused(_ paused: Bool, browser: VideoPlaybackBrowser, videoID: String) async throws -> VideoPlaybackSnapshot {
        controls.append(.init(paused: paused, videoID: videoID))
        if controlDelay { try await Task.sleep(for: .milliseconds(100)) }
        if controlFailure { throw VideoPlaybackReadError.temporary("Playback rejected") }
        controlledPaused = paused
        return .init(url: "https://www.youtube.com/watch?v=\(videoID)", time: 3, paused: paused, rate: 1, ad: false, unsupported: false)
    }
    let steps: [Step]
    private var cursor = 0
    private(set) var requests: [Request] = []
    init(steps: [Step]) { self.steps = steps }
    func read(_ browser: VideoPlaybackBrowser, initial: Bool, videoID: String?) async throws -> VideoPlaybackSnapshot {
        requests.append(.init(initial: initial, videoID: videoID))
        let step = steps[min(cursor, steps.count - 1)]
        cursor += 1
        switch step {
        case .snapshot(let snapshot): return .init(url: snapshot.url, time: snapshot.time, paused: controlledPaused ?? snapshot.paused, rate: snapshot.rate, ad: snapshot.ad, unsupported: snapshot.unsupported, title: snapshot.title)
        case .failure(let error): throw error
        }
    }
}
