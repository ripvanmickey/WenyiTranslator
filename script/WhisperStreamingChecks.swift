import Foundation
@main struct Checks {
 static func main() {
  typealias Segment = WhisperStreamingHypothesis.Segment
  let voice = [Float](repeating: 0.1, count: 16000)
  var window = WhisperCaptionWindow()
  var policy = WhisperStreamingHypothesis()
  precondition(window.append(voice + voice + voice + voice, now: 4))
  let snapshot = window.snapshot()!
  let segments = (0..<4).map { Segment(text:"phrase \($0)",start:Double($0),end:Double($0+1)) }
  let plan = policy.decide(segments:segments,snapshot:snapshot)
  precondition(plan.confirmed == Array(segments.prefix(2)))
  precondition(plan.provisional == Array(segments.suffix(2)))
  precondition(policy.decide(segments:Array(segments.prefix(2)),snapshot:snapshot).confirmed.isEmpty)
  precondition(window.advance(snapshot,frames:32000))
  precondition(window.samples.count == 32000 && window.snapshot() == nil)
  print("PASS upstream policy: keep two trailing segments, commit on first decode, preserve PCM tail")

  var rolling = WhisperCaptionWindow()
  var confirmed:[String] = []
  var peak = 0
  for second in 0..<300 {
   precondition(rolling.append(voice,now:Double(second+1)))
   peak=max(peak,rolling.samples.count)
   guard let snap=rolling.snapshot() else { fatalError("Missing snapshot") }
   let start=snap.startFrame/16000
   let decoded=(0..<(snap.audio.count/16000)).map { index in
    Segment(text:"word\(start+index)",start:Double(index),end:Double(index+1))
   }
   let decision=policy.decide(segments:decoded,snapshot:snap)
   if decision.confirmedEnd>0 {
    confirmed += decision.confirmed.map(\.text)
    precondition(rolling.advance(snap,frames:Int(decision.confirmedEnd*16000)))
   }
  }
  precondition(confirmed == (0..<298).map { "word\($0)" })
  precondition(rolling.samples.count == 32000 && peak<=48000)
  print("PASS synthetic 300s: ordered confirmation, two-second tail; not a model performance test")

  var stalled = WhisperCaptionWindow()
  precondition(stalled.append([Float](repeating:0.1,count:16000*12),now:12))
  let old=stalled.snapshot()!
  stalled.retryAfterNewAudio(old)
  precondition(stalled.append(voice,now:13))
  let retry=stalled.snapshot()!
  precondition(retry.endFrame>old.endFrame, "Empty-result retries must include new context beyond 12s")
  precondition(stalled.samples.count==16000*13)
  let malformed=Segment(text:"invalid",start:0,end:Double.nan)
  precondition(policy.decide(segments:[malformed]+segments,snapshot:snapshot).confirmed.isEmpty)
  print("PASS empty retry expands context without dropping audio; malformed timestamps cannot confirm later segments")
 }
}
