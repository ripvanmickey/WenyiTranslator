import AVFoundation
import CoreAudio

@main struct AudioTapChecks {
    static func main() throws {
        for rate in [44100.0, 48000.0] {
            for interleaved in [false, true] {
                let source = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate,
                    channels: 2, interleaved: interleaved)!
                let bridge = try CoreAudioTapCapture.PCMBridge(format: source.streamDescription.pointee, sampleRate: 16000)
                var totalFrames = 0
                var retained: CMSampleBuffer?
                for block in 0..<50 {
                    let pcm = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: 480)!
                    pcm.frameLength = 480
                    let buffers = UnsafeMutableAudioBufferListPointer(pcm.mutableAudioBufferList)
                    for buffer in buffers {
                        let samples = buffer.mData!.assumingMemoryBound(to: Float.self)
                        for i in 0..<(Int(buffer.mDataByteSize) / 4) {
                            samples[i] = Float(sin(Double(i + block * 480) * 0.1)) * 0.3
                        }
                    }
                    guard let sample = bridge.convert(pcm.audioBufferList) else { fatalError("missing converted PCM") }
                    let desc = CMAudioFormatDescriptionGetStreamBasicDescription(CMSampleBufferGetFormatDescription(sample)!)!.pointee
                    precondition(desc.mSampleRate == 16000 && desc.mChannelsPerFrame == 1 && desc.mBitsPerChannel == 16)
                    precondition(CMSampleBufferDataIsReady(sample))
                    totalFrames += CMSampleBufferGetNumSamples(sample)
                    retained = sample
                    // Callback data may immediately disappear or be reused; retained PCM must own its bytes.
                    for buffer in buffers { memset(buffer.mData!, 0, Int(buffer.mDataByteSize)) }
                }
                let expected = Double(50 * 480) * 16000 / rate
                precondition(abs(Double(totalFrames) - expected) < 64, "resampling duration changed")
                let block = CMSampleBufferGetDataBuffer(retained!)!
                var length = 0
                var bytes: UnsafeMutablePointer<Int8>?
                precondition(CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil,
                    totalLengthOut: &length, dataPointerOut: &bytes) == noErr)
                precondition(length > 0 && UnsafeBufferPointer(start: bytes, count: length).contains { $0 != 0 }, "PCM did not retain copied bytes")
                print("PASS \(Int(rate)) Hz stereo interleaved=\(interleaved) → 16k mono, duration and copied ownership")
            }
        }
        // Stop must be safe before start and on repeated teardown, without requesting recording permission.
        let capture = CoreAudioTapCapture()
        capture.stop(); capture.stop()
        print("PASS idempotent unused teardown; no hardware recording started")
    }
}
