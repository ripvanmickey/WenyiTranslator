import Foundation

@main
struct VideoSubtitleChecks {
    static func main() throws {
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
        if CommandLine.arguments.count > 1 {
            let real = try VideoSubtitleTimeline.parse(Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
            precondition(!real.isEmpty)
            print("PASS public YouTube VTT: \(real.count) timed cues")
        }
        print("PASS YouTube URL validation, VTT/SRT parsing, overlap normalization, backward/forward seek, subtitle gaps, silence and bounded speech ranges")
    }
}
