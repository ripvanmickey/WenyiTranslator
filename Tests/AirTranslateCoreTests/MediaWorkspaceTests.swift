import AppKit
import SwiftUI
import Foundation
import Testing
import AirTranslateCore
@testable import AirTranslate

@Suite(.serialized)
@MainActor
struct MediaWorkspaceTests {
    @Test func stoppingDuringReconnectCancelsFurtherReadsAndUnlocksSettings() async throws {
        let reader = ScriptedPlaybackReader(steps: [.failure(.temporary("Window transition"))])
        let model = VideoSubtitlePreloadStore(connection: reader)
        model.connect()
        try await waitForPlayback { model.connectionStatus.contains("正在恢复") }
        #expect(model.isConnecting)
        #expect(model.isConfigurationLocked)
        model.performMainAction()
        #expect(!model.isConfigurationLocked)
        let stoppedCount = await reader.requests.count
        try await Task.sleep(for: .milliseconds(650))
        #expect(await reader.requests.count == stoppedCount)
        #expect(model.connectionStatus == "未连接浏览器")
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
        try await waitForPlayback { model.connectionStatus.contains("正在恢复") }
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

    @Test func browserTrackingScriptsCompileForBothSupportedBrowsers() {
        for browser in VideoPlaybackBrowser.allCases {
            for initial in [true, false] {
                let appPath = browser == .chrome ? "/Applications/Google Chrome.app" : "/Applications/Safari.app"
                let source = VideoBrowserConnection.scriptSource(browser, initial: initial, videoID: "PMGSdzyRZUw", chromeTabID: 42)
                    .replacingOccurrences(of: "tell application id \"\(browser.bundleID)\"", with: "tell application \"\(appPath)\"")
                var details: NSDictionary?
                let script = NSAppleScript(source: source)
                #expect(script?.compileAndReturnError(&details) == true, "\(browser.title): \(details?.description ?? "")")
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
            }
        }
    }

    @Test func mediaActionNeverNeedsAnAudioCaptureSession() {
        let model = VideoSubtitlePreloadStore()
        #expect(!model.canPerformMainAction)
        model.videoURL = "https://www.youtube.com/watch?v=PMGSdzyRZUw"
        #expect(model.canPerformMainAction)
        #expect(model.mainActionTitle == "开始预加载")
        model.input = .imported
        #expect(!model.canPerformMainAction)
        model.isPreparing = true
        #expect(model.canPerformMainAction)
        #expect(model.mainActionTitle == "停止准备")
        model.isPreparing = false
        model.isConnected = true
        #expect(model.mainActionTitle == "停止同步")
        model.performMainAction()
        #expect(!model.isConnected)
        #expect(model.activeCue == nil)
    }

    @Test func mediaOutputChoiceDoesNotChangeCachedTranslations() {
        let model = VideoSubtitlePreloadStore()
        model.document = .init(videoID: "PMGSdzyRZUw", title: "Fixture", sourceLanguage: "ja-JP", targetLanguage: "zh-CN", provider: "index", input: "youtube", cues: [.init(id: 0, start: 0, end: 3, source: "こんにちは", translation: "你好")], completed: true)
        model.activeCue = model.document?.cues.first
        #expect(model.mainActionTitle == "连接视频")
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
        #expect(MediaWorkspaceLayout.minimumWindowWidth(media: false) == 900)
        #expect(MediaWorkspaceLayout.minimumWindowWidth(media: true) == 1201)
        for width in stride(from: 1201.0, through: 2400.0, by: 37) {
            let captionWidth = width - MediaWorkspaceLayout.sidebarWidth(for: width) - 1
            #expect(captionWidth >= 900)
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

private actor ScriptedPlaybackReader: VideoPlaybackReading {
    enum Step: Sendable { case snapshot(VideoPlaybackSnapshot), failure(VideoPlaybackReadError) }
    struct Request: Sendable { let initial: Bool; let videoID: String? }
    let steps: [Step]
    private var cursor = 0
    private(set) var requests: [Request] = []
    init(steps: [Step]) { self.steps = steps }
    func read(_ browser: VideoPlaybackBrowser, initial: Bool, videoID: String?) async throws -> VideoPlaybackSnapshot {
        requests.append(.init(initial: initial, videoID: videoID))
        let step = steps[min(cursor, steps.count - 1)]
        cursor += 1
        switch step {
        case .snapshot(let snapshot): return snapshot
        case .failure(let error): throw error
        }
    }
}
