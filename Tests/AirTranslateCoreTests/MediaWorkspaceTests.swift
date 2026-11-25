import Foundation
import Testing
import AirTranslateCore
@testable import AirTranslate

@Suite(.serialized)
@MainActor
struct MediaWorkspaceTests {
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
}
