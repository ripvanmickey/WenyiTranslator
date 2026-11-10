import Foundation
import SileroVAD

/// Confined to the recognition worker, never called from the capture callback.
final class SileroSpeechDetector {
    private let vad: SileroVAD
    private var context = [Float](repeating: 0, count: 64)
    init(modelURL: URL? = nil) throws {
        if let modelURL { vad = try SileroVAD(modelURL: modelURL) }
        else { vad = try SileroVAD(bundle: .main) }
    }
    func reset() {
        vad.reset()
        context = [Float](repeating: 0, count: 64)
    }
    func probability(_ samples: [Float]) throws -> Float {
        precondition(samples.count == 512)
        // Silero's 576-input export expects 64 samples of preceding context
        // followed by 512 new samples, rather than 576 non-overlapping samples.
        let probability = try vad.process(context + samples)
        guard probability.isFinite, (0...1).contains(probability) else {
            throw NSError(domain: "SileroVAD", code: 1, userInfo: [NSLocalizedDescriptionKey: "Silero VAD 返回无效结果，已停止，未丢弃待确认音频。"])
        }
        context = Array(samples.suffix(64))
        return probability
    }
}
