import Foundation

@main
struct VideoSubtitleChecks {
    static func main() async throws {
        let id = "M7lc1UVf-VE"
        for url in ["https://www.youtube.com/watch?v=\(id)&t=20", "https://youtu.be/\(id)",
                    "https://m.youtube.com/watch?v=\(id)", "https://youtube.com/shorts/\(id)"] {
            let reference = try YouTubeVideoReference(url)
            precondition(reference.id == id)
        }
        for bad in ["https://youtube.com.evil.example/watch?v=\(id)", "https://user:pass@youtube.com/watch?v=\(id)",
                    "file:///tmp/video", "https://youtube.com/watch?v=abc", "https://youtube.com:8443/watch?v=\(id)",
                    "https://example.org/\(id)"] {
            precondition((try? YouTubeVideoReference(bad)) == nil)
        }
        let vtt = """
        WEBVTT

        00:00:01.000 --> 00:00:03.000 align:start position:0%
        <c>Hello &amp; welcome.</c>

        00:00:02.500 --> 00:00:05.000
        A second sentence.

        00:00:07.000 --> 00:00:08.000
        Final.
        """
        let cues = try VideoSubtitleTimeline.parse(Data(vtt.utf8))
        precondition(cues.count == 3 && cues[0].source == "Hello & welcome.")
        precondition(cues[0].end == 2.5)
        for (time, expected) in [(0.0, nil), (1.0, 0), (2.49, 0), (2.5, 1), (5.0, nil), (7.5, 2), (1.5, 0)] as [(Double, Int?)] {
            precondition(VideoSubtitleTimeline.activeCue(in: cues, at: time)?.id == expected)
        }
        precondition(VideoSubtitleTimeline.activeCue(in: cues, at: .nan) == nil)
        let srt = VideoSubtitleTimeline.srt(cues)
        let roundTrip = try VideoSubtitleTimeline.parse(Data(srt.utf8))
        precondition(roundTrip == cues)
        let rolling = """
        WEBVTT

        00:00:01.000 --> 00:00:02.000
        Hello<00:00:01.500><c> everyone</c>

        00:00:02.000 --> 00:00:02.010
        Hello everyone

        00:00:02.010 --> 00:00:03.000
        Hello everyone
        Welcome<00:00:02.500><c> back</c>
        """
        let rolled = try VideoSubtitleTimeline.parse(Data(rolling.utf8))
        precondition(rolled.map(\.source) == ["Hello everyone", "Welcome back"])
        let duplicate = VideoSubtitleTimeline.normalized([
            .init(id: 0, start: 0, end: 2, source: "same"), .init(id: 1, start: 1, end: 3, source: "same")])
        precondition(duplicate.count == 1 && duplicate[0].end == 3)
        let silence = VideoSpeechSegmentation.ranges(energies: Array(repeating: 0, count: 500), frameDuration: 0.02, duration: 10)
        precondition(silence.isEmpty)
        let continuous = VideoSpeechSegmentation.ranges(energies: Array(repeating: 0.1, count: 2_000), frameDuration: 0.02, duration: 40)
        precondition(continuous.count == 3)
        for (index, interval) in continuous.enumerated() {
            precondition(interval.lowerBound >= 0 && interval.upperBound <= 40 && interval.upperBound - interval.lowerBound <= 15.03)
            if index > 0 { precondition(interval.lowerBound >= continuous[index - 1].upperBound) }
        }
        let paused = VideoSpeechSegmentation.ranges(energies: Array(repeating: 0.1, count: 40) + Array(repeating: 0, count: 50) + Array(repeating: 0.1, count: 40), frameDuration: 0.02, duration: 2.6)
        precondition(paused.count == 2 && paused[0].upperBound < paused[1].lowerBound)
        try await progressiveChecks()
        if CommandLine.arguments.count > 1 {
            let real = try VideoSubtitleTimeline.parse(Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
            precondition(!real.isEmpty)
            print("PASS public YouTube VTT: \(real.count) timed cues")
        }
        print("PASS YouTube URL validation, VTT/SRT parsing, overlap normalization, backward/forward seek, subtitle gaps, silence and bounded speech ranges")
    }
    @MainActor
    static func progressiveChecks() async throws {
        enum SimulatedFailure: Error { case translation }
        let ranges = [VideoAudioRange(start: 0, end: 4), .init(start: 5, end: 8), .init(start: 9, end: 12)]
        var document = VideoSubtitleDocument(videoID: "M7lc1UVf-VE", title: "test", sourceLanguage: "ja-JP",
            targetLanguage: "zh-CN", provider: "index", input: "openAI", cues: [], audioProgress: .init(ranges: ranges))
        var requested: [Int] = []
        var events: [String] = []
        try await VideoSubtitleProgressivePipeline.run(ranges: ranges, from: 0) { index, _ in
            requested.append(index); events.append("request\(index)")
            if index == 1 {
                // The first complete translation must already be playable before later ASR requests.
                precondition(document.cues.first?.translation == "translated first")
                precondition(VideoSubtitleTimeline.activeCue(in: document.cues, at: 2)?.translation == "translated first")
            }
            return index == 1 ? " " : (index == 0 ? "first" : "last")
        } consume: { cue, done, _ in
            if var cue { cue.translation = "translated " + cue.source; document.cues.append(cue) }
            document.audioProgress?.nextRange = done
            events.append("delivered\(done)")
        }
        precondition(events == ["request0", "delivered1", "request1", "delivered2", "request2", "delivered3"])
        precondition(document.cues.map(\.id) == [0, 2] && document.audioProgress?.isRecognitionComplete == true)

        // Persist recognition before a failed translation; resuming must not upload that audio again.
        document.cues = []; document.audioProgress = .init(ranges: ranges); requested = []
        do {
            try await VideoSubtitleProgressivePipeline.run(ranges: ranges, from: 0) { index, _ in
                requested.append(index); return "phrase\(index)"
            } consume: { cue, done, _ in
                if let cue { document.cues.append(cue) }
                document.audioProgress?.nextRange = done
                throw SimulatedFailure.translation
            }
            preconditionFailure("Expected a translation failure")
        } catch SimulatedFailure.translation { }
        let cached = try JSONEncoder().encode(document)
        document = try JSONDecoder().decode(VideoSubtitleDocument.self, from: cached)
        precondition(document.completed == false && document.audioProgress?.nextRange == 1)
        document.cues[0].translation = "retried cached text"
        try await VideoSubtitleProgressivePipeline.run(ranges: ranges, from: document.audioProgress!.nextRange) { index, _ in
            requested.append(index); return "phrase\(index)"
        } consume: { cue, done, _ in
            if var cue { cue.translation = "translated"; document.cues.append(cue) }
            document.audioProgress?.nextRange = done
        }
        precondition(requested == [0, 1, 2] && document.cues.count == 3)
        precondition(document.cues[0].translation == "retried cached text")
        precondition(document.audioProgress?.isRecognitionComplete == true && !document.completed)

        // Old caches omit the new checkpoint and must remain fully recognized.
        var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(document)) as! [String: Any]
        old.removeValue(forKey: "audioProgress")
        let oldDocument = try JSONDecoder().decode(VideoSubtitleDocument.self, from: JSONSerialization.data(withJSONObject: old))
        precondition(oldDocument.audioProgress == nil && oldDocument.cues == document.cues)

        let cancelled = Task { @MainActor in
            var requests = 0
            do {
                try await VideoSubtitleProgressivePipeline.run(ranges: ranges, from: 0) { _, _ in
                    requests += 1; return "whole phrase"
                } consume: { _, _, _ in
                    withUnsafeCurrentTask { $0?.cancel() }
                }
                preconditionFailure("Expected cancellation before the next audio request")
            } catch is CancellationError { }
            return requests
        }
        let requestCount = try await cancelled.value
        precondition(requestCount == 1)
        print("PASS progressive whole-phrase delivery, partial-cache checkpoints, resume without repeated ASR, legacy caches and cancellation")
    }

}
