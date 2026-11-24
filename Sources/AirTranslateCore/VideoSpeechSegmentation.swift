import Foundation

public enum VideoSpeechSegmentation {
    public static func ranges(energies: [Double], frameDuration: Double, duration: Double) -> [ClosedRange<Double>] {
        guard frameDuration > 0, duration.isFinite, duration > 0 else { return [] }
        var result: [ClosedRange<Double>] = [], start: Double?, lastSpeech = 0.0
        for (index, energy) in energies.enumerated() {
            let time = min(duration, Double(index) * frameDuration)
            if energy.isFinite, energy >= 0.008 {
                if start == nil { start = max(result.last?.upperBound ?? 0, time - 0.12) }
                lastSpeech = min(duration, time + frameDuration)
            }
            if let begin = start, (time - lastSpeech >= 0.45 || time - begin >= 15) {
                let end = min(duration, min(time + frameDuration, lastSpeech + 0.16))
                if end - begin >= 0.12 { result.append(begin...end) }
                start = nil
            }
        }
        if let begin = start, lastSpeech > begin { result.append(begin...min(duration, lastSpeech + 0.16)) }
        return result
    }
}
