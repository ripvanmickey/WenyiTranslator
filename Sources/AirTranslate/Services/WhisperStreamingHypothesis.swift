import Foundation

/// External-PCM adaptation of Argmax AudioStreamTranscriber's confirmation policy.
/// Upstream: Vendor/argmax-oss-swift-main/Sources/WhisperKit/Core/Audio/AudioStreamTranscriber.swift
/// Copyright © 2024 Argmax, Inc. See Vendor/argmax-oss-swift-main/LICENSE.
/// Keep the latest two segments provisional; advance only through confirmed timestamps.
/// Unlike upstream microphone capture, our bounded PCM window physically removes committed audio.
struct WhisperStreamingHypothesis {
    struct Segment: Equatable, Sendable {
        let text: String
        let start: Double
        let end: Double
    }
    struct Decision {
        let confirmed: [Segment]
        let provisional: [Segment]
        var confirmedEnd: Double { confirmed.last?.end ?? 0 }
    }
    mutating func decide(segments: [Segment], snapshot: WhisperCaptionWindow.Snapshot) -> Decision {
        var end = 0.0
        var valid: [Segment] = []
        for segment in segments {
            // Do not commit across a malformed or out-of-order segment.
            guard !segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  segment.start.isFinite, segment.end.isFinite,
                  segment.start >= 0, segment.end > segment.start,
                  segment.start >= end - 0.02,
                  segment.end <= Double(snapshot.audio.count) / 16000 + 0.2 else { break }
            valid.append(segment)
            end = segment.end
        }
        // Endpoint flushing is our adapter's addition: otherwise a short final
        // utterance could remain provisional forever after capture stops receiving speech.
        let count = snapshot.isFinal ? valid.count : max(0, valid.count - 2)
        return Decision(confirmed: Array(valid.prefix(count)), provisional: Array(valid.dropFirst(count)))
    }

}

struct WhisperDecodeStatistics {
    var count = 0
    var inFlightSince: TimeInterval? = nil
    var lastMilliseconds: Double = 0
    var totalSeconds: Double = 0
    var submittedSeconds: Double = 0
    var maximumBufferSeconds: Double = 0
    var stableCommits = 0
    var emptyResults = 0
    var noProgress = 0
    var noSegmentResults = 0
    var invalidFinalResults = 0
    mutating func record(seconds: Double, audioSeconds: Double, bufferSeconds: Double, advanced: Bool) {
        count += 1; lastMilliseconds = seconds * 1000
        totalSeconds += seconds; submittedSeconds += audioSeconds
        maximumBufferSeconds = max(maximumBufferSeconds, bufferSeconds)
        noProgress = advanced ? 0 : noProgress + 1
    }
    func summary(window: WhisperCaptionWindow) -> String {
        let input = Double(window.totalFrames) / 16000
        let advanced = Double(window.startFrame) / 16000
        let buffered = Double(window.samples.count) / 16000
        let live = inFlightSince.map { String(format: "当前识别尚未返回：%.0f ms\n", max(0, ProcessInfo.processInfo.systemUptime - $0) * 1000) } ?? "当前无正在执行的识别任务\n"
        return live + "分段诊断：停顿收尾解码 \(window.vadEndpointDecodes) 次 · 长窗口收尾解码 \(window.boundedWindowDecodes) 次 · 无片段结果 \(noSegmentResults) 次 · 收尾有字但无有效确认 \(invalidFinalResults) 次\n" + "实时优先：跳过 \(window.realtimeRecoveries) 次 · 累计跳过待确认音频 \(String(format: "%.2f", Double(window.skippedFrames) / 16000)) 秒（可能含已显示内容）\n" + "Silero VAD：已检测 \(window.vadChunks) 块 · 已释放非人声 \(String(format: "%.2f", Double(window.nonSpeechReleasedFrames) / 16000)) 秒\n" + String(format: "WhisperKit 运行诊断（每次开始重置）\n已接收 %.2f 秒 · 已推进 %.2f 秒 · 当前待确认 %.2f 秒\n待确认峰值 %.2f 秒 · 识别 %d 次 · 最近计算 %.0f ms\n累计计算 %.2f 秒 · 累计送入识别（含复算） %.2f 秒\n官方策略片段确认 %d 次 · 空结果 %d 次 · 连续未推进 %d 次\n当前更新门槛 %.0f ms · 当前窗口上限 %.1f 秒", input, advanced, buffered,
            maximumBufferSeconds, count, lastMilliseconds, totalSeconds, submittedSeconds,
            stableCommits, emptyResults, noProgress,
            Double(window.updateStrideFrames) / 16, Double(window.contextFrames) / 16000)
    }
}
