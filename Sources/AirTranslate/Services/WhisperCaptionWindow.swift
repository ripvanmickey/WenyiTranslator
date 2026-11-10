import Foundation

/// A single bounded utterance, not an unbounded queue of decoding jobs.
struct WhisperCaptionWindow {
    static let rate = 16_000
    static let maximumWindowFrames = rate * 8
    struct Snapshot: Sendable {
        let id: Int
        let epoch: UInt64
        let revision: Int
        let audio: [Float]
        let startFrame: Int
        let endFrame: Int
        let speechEndFrame: Int
        let audioEndUptime: TimeInterval
        let isFinal: Bool
    }
    var samples: [Float] = []
    var startFrame = 0
    var totalFrames = 0
    var lastVoiceFrame = 0
    var lastDecodedFrames = 0
    var lastArrival: TimeInterval = 0
    var id = 0
    var epoch: UInt64 = 0
    var revision = 0
    var hasVoice = false
    var retryAfterFrame: Int? = nil
    var updateStrideFrames = Int(Double(rate) * 0.35)
    var contextFrames = maximumWindowFrames
    private var lastSnapshotStart = -1
    private var lastSnapshotEnd = -1
    private var lastSnapshotWasFinal = false

    var prioritizesRealtime = false
    var realtimeRecoveries = 0
    var skippedFrames = 0
    var usesSilero = false
    var classifiedThroughFrame = 0
    var nonSpeechReleasedFrames = 0
    var vadChunks = 0
    private var voiceRanges: [Range<Int>] = []
    // Hysteresis follows Whisper-Streaming/Silero VADIterator's design:
    // https://github.com/ufal/whisper_streaming/blob/main/silero_vad_iterator.py
    // Local tuning: start .4, end .25, require 320ms below end threshold.
    private var vadSpeaking = false
    private var vadQuietFrames = 0
    private var vadBoundaries: [Int] = []
    var vadEndpointDecodes = 0
    var boundedWindowDecodes = 0

    func vadInput() -> (epoch: UInt64, start: Int, audio: [Float])? {
        let start = max(startFrame, classifiedThroughFrame)
        let count = (totalFrames - start) / 512 * 512
        guard usesSilero, count > 0 else { return nil }
        let offset = start - startFrame
        return (epoch, start, Array(samples[offset..<(offset + count)]))
    }
    mutating func applyVAD(start: Int, probabilities: [Float], epoch: UInt64) {
        guard usesSilero, self.epoch == epoch, start == max(startFrame, classifiedThroughFrame) else { return }
        for (index, probability) in probabilities.enumerated() {
            let end = start + (index + 1) * 512
            // Low threshold deliberately keeps uncertain speech. Classification
            // is statistical, so leading/trailing padding is retained as well.
            if !vadSpeaking && probability >= 0.4 {
                vadSpeaking = true; vadQuietFrames = 0
            }
            if vadSpeaking && probability >= 0.25 {
                vadQuietFrames = 0
                let lower = max(startFrame, end - 512 - 4800)
                let upper = min(totalFrames, end + 3200)
                if let previous = voiceRanges.last, previous.upperBound >= lower {
                    voiceRanges[voiceRanges.count - 1] = previous.lowerBound..<max(upper, previous.upperBound)
                } else { voiceRanges.append(lower..<upper) }
                lastVoiceFrame = max(lastVoiceFrame, upper)
            } else if vadSpeaking {
                vadQuietFrames += 512
                if vadQuietFrames >= 5120 {
                    vadSpeaking = false; vadQuietFrames = 0
                    if lastVoiceFrame > startFrame { vadBoundaries.append(lastVoiceFrame) }
                }
            }
        }
        classifiedThroughFrame = start + probabilities.count * 512
        vadChunks += probabilities.count
        voiceRanges.removeAll { $0.upperBound <= startFrame }
        hasVoice = !voiceRanges.isEmpty
        let safeEnd = max(startFrame, classifiedThroughFrame - 4800)
        let releaseEnd = min(safeEnd, voiceRanges.first?.lowerBound ?? safeEnd)
        if releaseEnd > startFrame {
            let frames = releaseEnd - startFrame
            samples.removeFirst(frames)
            startFrame = releaseEnd
            lastDecodedFrames = max(0, lastDecodedFrames - frames)
            nonSpeechReleasedFrames += frames
            lastSnapshotStart = -1; lastSnapshotEnd = -1
        }
    }

    mutating func append(_ incoming: [Float], now: TimeInterval) -> Bool {
        // Oversized capture batches still fail; normal backlog recovers below this bound.
        guard samples.count + incoming.count <= Self.rate * 20 else { return false }
        if samples.isEmpty { startFrame = totalFrames }
        totalFrames += incoming.count
        samples.append(contentsOf: incoming)
        lastArrival = now
        let energy = incoming.reduce(Float.zero) { $0 + $1 * $1 } / Float(max(1, incoming.count))
        if !usesSilero && energy > 0.000_025 { lastVoiceFrame = totalFrames; hasVoice = true }
        if !usesSilero && !hasVoice && samples.count > Self.rate {
            samples.removeAll(keepingCapacity: true)
            startFrame = totalFrames
        }
        if prioritizesRealtime && samples.count >= Self.rate * 12 {
            let keep = Self.rate * 4
            let skipped = samples.count - keep
            samples.removeFirst(skipped)
            startFrame += skipped
            skippedFrames += skipped
            realtimeRecoveries += 1
            // Invalidate in-flight ASR and VAD. Reclassify the retained tail with
            // fresh recurrent state; old results must never advance this window.
            epoch &+= 1; id += 1; revision = 0
            lastDecodedFrames = 0; retryAfterFrame = nil
            contextFrames = Self.rate * 6
            lastSnapshotStart = -1; lastSnapshotEnd = -1
            voiceRanges.removeAll(); classifiedThroughFrame = startFrame
            vadSpeaking = false; vadQuietFrames = 0; vadBoundaries.removeAll()
            hasVoice = usesSilero ? false : lastVoiceFrame > startFrame
        }
        return true
    }
    mutating func snapshot() -> Snapshot? {
        guard hasVoice, samples.count >= Self.rate / 2 else { return nil }
        if let retryAfterFrame, totalFrames < retryAfterFrame { return nil }
        retryAfterFrame = nil
        let availableFrames = usesSilero ? max(0, classifiedThroughFrame - startFrame) : samples.count
        guard availableFrames >= Self.rate / 2 else { return nil }
        // Keep past endpoints even when another speaker starts before ASR returns.
        // Otherwise the latest voice activity can erase the previous turn boundary.
        let boundary = usesSilero ? vadBoundaries.first(where: {
            $0 - startFrame >= Self.rate / 2 && $0 <= startFrame + availableFrames
        }) : nil
        let boundaryCount = boundary.map { $0 - startFrame }
        let bounded = availableFrames >= contextFrames
        let final = boundaryCount != nil || (usesSilero ? classifiedThroughFrame : totalFrames) - lastVoiceFrame >= Int(Double(Self.rate) * 0.55) || bounded
        guard final || samples.count - lastDecodedFrames >= updateStrideFrames else { return nil }
        let count = min(availableFrames, contextFrames, boundaryCount ?? availableFrames)
        guard lastSnapshotStart != startFrame || lastSnapshotEnd != startFrame + count || (final && !lastSnapshotWasFinal) else { return nil }
        lastSnapshotStart = startFrame; lastSnapshotEnd = startFrame + count; lastSnapshotWasFinal = final
        lastDecodedFrames = count
        revision += 1
        if boundaryCount == count { vadEndpointDecodes += 1 }
        else if bounded { boundedWindowDecodes += 1 }
        let endFrame = startFrame + count
        let speechEndFrame = min(lastVoiceFrame, endFrame)
        return Snapshot(id: id, epoch: epoch, revision: revision, audio: Array(samples.prefix(count)),
            startFrame: startFrame, endFrame: endFrame, speechEndFrame: speechEndFrame,
            audioEndUptime: lastArrival - Double(totalFrames - speechEndFrame) / Double(Self.rate), isFinal: final)
    }
    mutating func retryAfterNewAudio(_ snapshot: Snapshot) {
        guard epoch == snapshot.epoch, id == snapshot.id else { return }
        contextFrames = min(Self.rate * (prioritizesRealtime ? 10 : 18), contextFrames + Self.rate * 2)
        retryAfterFrame = totalFrames + updateStrideFrames
    }
    static func isNonSpeech(_ probabilities: [Float]) -> Bool {
        !probabilities.isEmpty && probabilities.allSatisfy { $0.isFinite && $0 >= 0.8 }
    }
    static func consumedFrames(_ snapshot: Snapshot, recognizedEndSeconds: Double) -> Int {
        guard recognizedEndSeconds.isFinite, recognizedEndSeconds > 0 else { return 0 }
        let count = Int(min(Double(snapshot.audio.count), (recognizedEndSeconds * Double(rate)).rounded(.down)))
        // Only trailing low-energy audio may be cleared beyond the decoder's timestamp.
        return snapshot.startFrame + count >= snapshot.speechEndFrame ? snapshot.audio.count : count
    }
    mutating func adapt(toDecodeSeconds seconds: Double) {
        guard seconds.isFinite, seconds >= 0 else { return }
        updateStrideFrames = Int(min(0.9, max(0.35, seconds * 0.65)) * Double(Self.rate))
    }
    @discardableResult
    mutating func advance(_ snapshot: Snapshot, frames: Int) -> Bool {
        guard epoch == snapshot.epoch, id == snapshot.id, startFrame == snapshot.startFrame,
              frames > 0, frames <= snapshot.audio.count, frames <= samples.count else { return false }
        samples.removeFirst(frames)
        startFrame += frames
        lastDecodedFrames = snapshot.audio.count - frames
        retryAfterFrame = nil; contextFrames = prioritizesRealtime ? Self.rate * 6 : Self.maximumWindowFrames
        // The retained tail has already been decoded and displayed. Wait for new
        // audio instead of immediately recomputing exactly that same tail.
        lastSnapshotStart = startFrame; lastSnapshotEnd = snapshot.endFrame; lastSnapshotWasFinal = snapshot.isFinal
        id += 1
        voiceRanges.removeAll { $0.upperBound <= startFrame }
        vadBoundaries.removeAll { $0 <= startFrame }
        hasVoice = usesSilero ? !voiceRanges.isEmpty : lastVoiceFrame > startFrame
        return true
    }
    mutating func complete(_ snapshot: Snapshot, recognizedEndSeconds: Double? = nil) {
        guard snapshot.isFinal else { return }
        let count = recognizedEndSeconds.map { Self.consumedFrames(snapshot, recognizedEndSeconds: $0) } ?? snapshot.audio.count
        advance(snapshot, frames: count)
    }
    mutating func discardForPause() {
        samples.removeAll(keepingCapacity: true)
        startFrame = totalFrames
        lastDecodedFrames = 0
        hasVoice = false
        retryAfterFrame = nil
        contextFrames = prioritizesRealtime ? Self.rate * 6 : Self.maximumWindowFrames
        lastSnapshotStart = -1; lastSnapshotEnd = -1
        voiceRanges.removeAll()
        vadBoundaries.removeAll(); vadSpeaking = false; vadQuietFrames = 0
        classifiedThroughFrame = totalFrames
        epoch &+= 1
        id += 1
    }
}
