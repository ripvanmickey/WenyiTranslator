import Foundation
import AirTranslateCore

/// Unary ASR for the same bounded speech ranges used by the media checkpoint pipeline.
/// Requests are independent: no conversation history, keys in URLs or automatic paid retries.
enum GeminiVideoTranscription {
    static let modelID = "gemini-3.5-transcribe"
    static func request(audio: Data, languageCode: String, key: String) throws -> URLRequest {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw GeminiLiveTranslationError.missingAPIKey }
        guard !audio.isEmpty, audio.count <= 12_000_000 else { throw VideoSubtitleError.invalidAudio }
        let body: [String: Any] = [
            "model": modelID,
            "input": [["type": "audio", "data": audio.base64EncodedString(), "mime_type": "audio/mp4"]],
            "generation_config": ["transcription_config": ["language_codes": [languageCode]]]
        ]
        var request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/interactions")!)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2026-05-20", forHTTPHeaderField: "Api-Revision")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 60
        return request
    }

    static func transcribe(_ file: URL, language: LanguageOption, key: String, session: URLSession) async throws -> String {
        try Task.checkCancellation()
        let request = try request(audio: Data(contentsOf: file), languageCode: language.id, key: key)
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw GeminiLiveTranslationError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw VideoPreloadProblem(message: AppText.ui("Gemini 音轨识别失败（\(http.statusCode)）。请检查 API 密钥、模型权限、额度和网络。", "Gemini audio recognition failed (\(http.statusCode)). Check your API key, model access, quota, and network.", "Gemini 音声認識に失敗しました（\(http.statusCode)）。API キー、モデルの権限、利用枠、ネットワークを確認してください。"))
        }
        return try transcript(data)
    }

    static func transcript(_ data: Data) throws -> String {
        guard data.count <= 8_000_000,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["status"] as? String == "completed",
              let steps = root["steps"] as? [[String: Any]] else {
            throw GeminiLiveTranslationError.invalidResponse
        }
        let modelSteps = steps.filter { $0["type"] as? String == "model_output" }
        guard !modelSteps.isEmpty else { throw GeminiLiveTranslationError.invalidResponse }
        let content = modelSteps.flatMap { $0["content"] as? [[String: Any]] ?? [] }
        guard content.allSatisfy({ $0["type"] as? String == "text" && $0["text"] is String }) else {
            throw GeminiLiveTranslationError.invalidResponse
        }
        return content.compactMap { $0["text"] as? String }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
