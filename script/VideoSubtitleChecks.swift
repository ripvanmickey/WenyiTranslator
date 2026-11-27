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
        floatingCaptionChecks()
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
        try await sourceReviewChecks()
        if CommandLine.arguments.count > 1 {
            let real = try VideoSubtitleTimeline.parse(Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
            precondition(!real.isEmpty)
            print("PASS public YouTube VTT: \(real.count) timed cues")
        }
        print("PASS YouTube URL validation, VTT/SRT parsing, overlap normalization, backward/forward seek, subtitle gaps, silence and bounded speech ranges")
    }

    @MainActor
    static func sourceReviewChecks() async throws {
        enum SimulatedFailure: Error { case interrupted }
        struct Line: Decodable { let index: Int; let text: String; let editable: Bool }
        struct Request: Decodable { let lines: [Line] }
        let phrases = ["試乗車には4駆と2駆モデルがあります。", "肉モデルを試乗しました。", "出力は150kWです。",
                       "肉料理と鶏肉料理を選びました。"] + Array(repeating: "試乗の感想を話します。", count: 8)
        let initial = VideoSubtitleDocument(videoID: "M7lc1UVf-VE", title: "Synthetic test", sourceLanguage: "ja-JP",
            targetLanguage: "zh-CN", provider: "openAI", input: "openAI",
            cues: phrases.enumerated().map { index, text in
                .init(id: index * 2, start: Double(index * 3), end: Double(index * 3 + 2),
                      source: text, translation: "已有译文 \(index)")
            }, completed: true)
        // Legacy cache files have no review checkpoint.
        let oldCache = try JSONEncoder().encode(initial)
        let decoded = try JSONDecoder().decode(VideoSubtitleDocument.self, from: oldCache)
        precondition(decoded.reviewProgress == nil)

        let response = """
        {"corrections":[
          {"index":1,"original":"肉","replacement":"2駆","evidenceIndex":0,"evidence":"4駆と2駆モデル"},
          {"index":2,"original":"150kW","replacement":"160kW","evidenceIndex":0,"evidence":"4駆と2駆モデル"},
          {"index":3,"original":"肉","replacement":"2駆","evidenceIndex":0,"evidence":"4駆と2駆モデル"},
          {"index":10,"original":"試乗","replacement":"試作","evidenceIndex":0,"evidence":"4駆と2駆モデル"}
        ]}
        """
        var saved = decoded
        var translated: [String] = []
        var requests = 0
        do {
            try await VideoSubtitleReviewPipeline.run(document: decoded) { batch in
                requests += 1
                let payload = try JSONDecoder().decode(Request.self, from: JSONEncoder().encode(batch))
                if requests > 1 {
                    precondition(payload.lines.first?.index == 7 && payload.lines.first?.editable == false)
                    throw SimulatedFailure.interrupted
                }
                precondition(payload.lines.count == 12 && payload.lines.filter(\.editable).count == 10)
                return response
            } translate: { corrected in
                translated.append(corrected)
                return "试驾了两驱车型。"
            } commit: { document in saved = document }
            preconditionFailure("Expected interruption after one committed batch")
        } catch SimulatedFailure.interrupted { }

        precondition(translated == ["2駆モデルを試乗しました。"])
        precondition(saved.reviewProgress == .init(nextCue: 10, correctedCues: 1))
        precondition(saved.cues[1].source == translated[0] && saved.cues[1].translation == "试驾了两驱车型。")
        precondition(saved.cues[2...] == initial.cues[2...])
        precondition(saved.cues.map(\.id) == initial.cues.map(\.id))
        precondition(saved.cues.map(\.start) == initial.cues.map(\.start))
        precondition(saved.cues.map(\.end) == initial.cues.map(\.end))
        precondition(VideoSubtitleTimeline.srt(saved.cues).contains("2駆モデルを試乗しました。\n试驾了两驱车型。"))

        let resumed = try JSONDecoder().decode(VideoSubtitleDocument.self, from: JSONEncoder().encode(saved))
        try await VideoSubtitleReviewPipeline.run(document: resumed) { batch in
            let payload = try JSONDecoder().decode(Request.self, from: JSONEncoder().encode(batch))
            precondition(payload.lines.filter(\.editable).map(\.index) == [10, 11])
            return "{\"corrections\":[]}"
        } translate: { _ in
            preconditionFailure("Unchanged captions must not be translated again")
        } commit: { document in saved = document }
        precondition(saved.reviewProgress == .init(nextCue: 12, correctedCues: 1))
        try await VideoSubtitleReviewPipeline.run(document: saved) { _ in
            preconditionFailure("A finished cache must not request a second review")
        } translate: { _ in
            preconditionFailure("A finished cache must not request translation")
        } commit: { _ in
            preconditionFailure("A finished cache must not be written again")
        }

        do {
            try await VideoSubtitleReviewPipeline.run(document: initial) { _ in response } translate: { _ in "" } commit: { _ in
                preconditionFailure("Do not commit a correction without its replacement translation")
            }
            preconditionFailure("Expected an empty translation error")
        } catch VideoSubtitleReviewError.emptyTranslation { }
        print("PASS preceding context corrections, changed-cue translation, original timings, legacy cache and review resume")
    }

    static func floatingCaptionChecks() {
        let firstSource = "この車は発進するときの加速がとてもなめらかです。"
        let secondSource = "高速道路に入ってからも車内はとても静かです。"
        let firstTranslation = "这辆车刚开始起步时，加速的感觉非常平顺。"
        let secondTranslation = "驶入高速公路以后，车内也依然十分安静。"
        let cue = VideoSubtitleCue(id: 0, start: 10, end: 18,
            source: firstSource + secondSource, translation: firstTranslation + secondTranslation)

        let switchTime = cue.start + (cue.end - cue.start) * Double(firstSource.count) / Double(cue.source.count)
        let later = VideoSubtitleTimeline.floatingText(for: cue, at: switchTime + 0.01)
        let earlier = VideoSubtitleTimeline.floatingText(for: cue, at: switchTime - 0.01)
        precondition(earlier.source == firstSource && earlier.translation == firstTranslation)
        precondition(later.source == secondSource && later.translation == secondTranslation)
        precondition(VideoSubtitleTimeline.floatingText(for: cue, at: switchTime + 0.01).source == secondSource)
        let originalOnly = VideoSubtitleTimeline.floatingText(for: cue, at: 10, showsTranslation: false)
        precondition(originalOnly.source == firstSource && originalOnly.translation.isEmpty)
        let translationOnly = VideoSubtitleTimeline.floatingText(for: cue, at: 17.9, showsSource: false)
        precondition(translationOnly.source.isEmpty && translationOnly.translation == secondTranslation)
        let saved = VideoSubtitleTimeline.srt([cue])
        precondition(saved.contains(cue.source + "\n" + cue.translation))

        let short = VideoSubtitleCue(id: 1, start: 20, end: 24, source: "はい。", translation: "是的。")
        precondition(VideoSubtitleTimeline.floatingText(for: short, at: 23.9).source == short.source)
        var brief = cue
        brief.end = 11.5
        precondition(VideoSubtitleTimeline.floatingText(for: brief, at: 11.4).source == cue.source)

        let english = "The cabin stays remarkably quiet while the driver accelerates smoothly onto the highway"
        let englishCue = VideoSubtitleCue(id: 2, start: 25, end: 31, source: english)
        let englishStart = VideoSubtitleTimeline.floatingText(for: englishCue, at: 25).source
        let englishEnd = VideoSubtitleTimeline.floatingText(for: englishCue, at: 30.9).source
        precondition(englishStart + " " + englishEnd == english)
        print("PASS shorter floating cues, bilingual sentence boundaries, seek, single-language display and complete SRT export")
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
