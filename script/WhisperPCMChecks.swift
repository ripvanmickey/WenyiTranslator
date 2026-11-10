import AVFoundation
import Foundation

// Minimal language value needed by the separately compiled adapter checks.
struct LanguageOption: Sendable { let id: String }

@main struct WhisperPCMChecks {
    static func main() async throws {
        for format in [AVAudioCommonFormat.pcmFormatFloat32, .pcmFormatInt16] {
            let audioFormat = AVAudioFormat(commonFormat: format, sampleRate: 16000, channels: 1, interleaved: true)!
            let pcm = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: 320)!
            pcm.frameLength = 320
            if format == .pcmFormatFloat32 {
                for i in 0..<320 { pcm.floatChannelData![0][i] = 0.25 }
            } else {
                for i in 0..<320 { pcm.int16ChannelData![0][i] = 8192 }
            }
            let sample = CoreAudioTapCapture.sampleBuffer(pcm.audioBufferList, format: audioFormat.streamDescription.pointee)!
            let floats = WhisperKitSpeechTranscriber.floats(sample)!
            precondition(floats.count == 320 && floats.allSatisfy { abs($0 - 0.25) < 0.0001 })
        }
        print("PASS actual Whisper adapter converts Float32 and Int16 16k mono samples without changing amplitude")
        let options = WhisperKitSpeechTranscriber.decodingOptions(languageCode: "ja")
        precondition(options.windowClipTime == 0 && options.noSpeechThreshold == nil)
        print("PASS short live windows are not skipped by the SDK one-second padding")
        let transcriber = WhisperKitSpeechTranscriber()
        transcriber.stop(); transcriber.setPaused(true); transcriber.stop()
        do {
            try await transcriber.start(folder: "", base: URL(fileURLWithPath: "/tmp"),
                language: LanguageOption(id: "en-US"), update: { _, _ in fatalError("Unexpected transcript") },
                failure: { _ in fatalError("Unexpected runtime failure") })
            fatalError("Missing model must fail")
        } catch { precondition(error.localizedDescription.contains("准备 WhisperKit 模型")) }
        print("PASS absent model fails clearly; stop/pause safe without audio permission")
    }
}
