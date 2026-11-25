import Foundation
import Testing
@testable import AirTranslate

struct GeminiVideoTranscriptionTests {
    @Test func unaryASRRequestUsesGeminiKeyAndNoOpenAIEndpoint() throws {
        let request = try GeminiVideoTranscription.request(audio: Data([0, 1, 2]), languageCode: "ja-JP", key: "test-only-key")
        #expect(request.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/interactions")
        #expect(request.url?.query == nil)
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "test-only-key")
        let body = try #require(request.httpBody)
        let root = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(root["model"] as? String == "gemini-3.5-transcribe")
        let audio = try #require((root["input"] as? [[String: Any]])?.first)
        #expect(audio["mime_type"] as? String == "audio/mp4")
        #expect(audio["data"] as? String == "AAEC")
        let config = try #require(root["generation_config"] as? [String: Any])
        let transcription = try #require(config["transcription_config"] as? [String: Any])
        #expect(transcription["language_codes"] as? [String] == ["ja-JP"])
    }

    @Test func parsingRequiresCompletedModelOutputAndRejectsPartialResults() throws {
        let valid = Data(#"{"status":"completed","steps":[{"type":"user_input","content":[{"type":"text","text":"Do not echo"}]},{"type":"model_output","content":[{"type":"text","text":"こんにちは。"}]}]}"#.utf8)
        #expect(try GeminiVideoTranscription.transcript(valid) == "こんにちは。")
        for invalid in [#"{"status":"incomplete","steps":[]}"#, #"{"status":"failed","steps":[]}"#, #"{"status":"completed","steps":[]}"#, #"{}"#] {
            #expect(throws: (any Error).self) { try GeminiVideoTranscription.transcript(Data(invalid.utf8)) }
        }
        #expect(throws: (any Error).self) { try GeminiVideoTranscription.request(audio: Data(), languageCode: "ja-JP", key: "test-only-key") }
    }
}
