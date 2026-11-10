import Foundation

@main struct WhisperWindowChecks {
    static func main() {
        let voice = [Float](repeating: 0.1, count: 1600)
        let silence = [Float](repeating: 0, count: 1600)
        var window = WhisperCaptionWindow()
        for i in 0..<4 { precondition(window.append(voice, now: Double(i) * 0.1)) }
        precondition(window.snapshot() == nil, "Must not decode before 500ms")
        precondition(window.append(voice, now: 0.5))
        let first = window.snapshot()!
        precondition(!first.isFinal && first.audio.count == 8000)
        precondition(window.snapshot() == nil, "Unchanged audio cannot create more jobs")
        for i in 0..<4 { precondition(window.append(voice, now: 0.6 + Double(i) * 0.1)) }
        let next = window.snapshot()!
        precondition(next.id == first.id && next.revision > first.revision)
        for i in 0..<6 { precondition(window.append(silence, now: 1.0 + Double(i) * 0.1)) }
        let final = window.snapshot()!
        precondition(final.isFinal && abs(final.audioEndUptime - 0.9) < 0.001)
        // Audio arriving during decoding is preserved, never cleared with the old snapshot.
        precondition(window.append(voice, now: 1.6))
        window.complete(final)
        precondition(window.samples.count == voice.count && window.hasVoice)
        precondition(window.id == final.id + 1)
        window.discardForPause()
        precondition(window.samples.isEmpty && !window.hasVoice && window.epoch != final.epoch)
        precondition(window.append(voice, now: 2))
        window.complete(final)
        precondition(window.samples.count == voice.count, "Stale final cannot clear new session data")
        print("PASS 500ms initial window, 350ms update cadence, final silence, preserve new audio, pause epoch")

        var retry = WhisperCaptionWindow()
        precondition(retry.append([Float](repeating: 0.1, count: 8000), now: 0.5))
        let uncertain = retry.snapshot()!
        retry.retryAfterNewAudio(uncertain)
        precondition(retry.snapshot() == nil && retry.samples.count == 8000)
        precondition(retry.append([Float](repeating: 0.1, count: 5600), now: 0.85))
        precondition(retry.snapshot() != nil)
        precondition(!WhisperCaptionWindow.isNonSpeech([]))
        precondition(!WhisperCaptionWindow.isNonSpeech([0.9, 0.1]))
        precondition(WhisperCaptionWindow.isNonSpeech([0.9, 0.95]))
        print("PASS ambiguous empty result retains audio and waits for new input; explicit non-speech requires probabilities")
        var quiet = WhisperCaptionWindow()
        for _ in 0..<100 { precondition(quiet.append(silence, now: 1)) }
        precondition(quiet.snapshot() == nil && quiet.samples.count <= 16000)
        var overload = WhisperCaptionWindow()
        precondition(!overload.append([Float](repeating: 0.1, count: 320001), now: 1))
        print("PASS silence cannot trigger recognition; explicit 20s overload bound")
        var backlog = WhisperCaptionWindow()
        precondition(backlog.append([Float](repeating: 0.1, count: 16000 * 18), now: 18))
        let bounded = backlog.snapshot()!
        precondition(bounded.audio.count == 16000 * 8 && bounded.isFinal)
        backlog.complete(bounded, recognizedEndSeconds: 3)
        precondition(backlog.samples.count == 16000 * 15 && backlog.startFrame == 16000 * 3)
        let remainder = backlog.snapshot()!
        precondition(remainder.startFrame == 16000 * 3 && remainder.audio.count == 16000 * 8)
        let before = backlog.samples.count
        backlog.complete(remainder, recognizedEndSeconds: 0)
        precondition(backlog.samples.count == before)
        backlog.complete(remainder, recognizedEndSeconds: .nan)
        precondition(backlog.samples.count == before)
        print("PASS slow decoder: bound window to 8s, retain unrecognized 15s, reject empty/invalid coverage")

    }
}
