import Foundation
@main struct Checks {
 static func main() {
  var window=WhisperCaptionWindow();window.prioritizesRealtime=true;window.usesSilero=true
  let voice=[Float](repeating:0.1,count:16000)
  for _ in 0..<11 { precondition(window.append(voice,now:1)) }
  let oldVAD=window.vadInput()!
  window.applyVAD(start:oldVAD.start,probabilities:Array(repeating:0.9,count:oldVAD.audio.count/512),epoch:oldVAD.epoch)
  let oldSnapshot=window.snapshot()!
  precondition(window.append(voice,now:12))
  precondition(window.samples.count==4*16000 && window.startFrame==8*16000)
  precondition(window.realtimeRecoveries==1 && window.skippedFrames==8*16000)
  precondition(window.epoch != oldSnapshot.epoch && window.id != oldSnapshot.id)
  precondition(!window.advance(oldSnapshot,frames:16000))
  window.applyVAD(start:oldVAD.start,probabilities:[0.9],epoch:oldVAD.epoch)
  precondition(window.classifiedThroughFrame==window.startFrame && !window.hasVoice)
  let newInput=window.vadInput()!
  window.applyVAD(start:newInput.start,probabilities:Array(repeating:0.9,count:newInput.audio.count/512),epoch:newInput.epoch)
  let fresh=window.snapshot()!
  precondition(fresh.startFrame==8*16000 && fresh.id != oldSnapshot.id)
  print("PASS 12s backlog retains latest 4s, rejects stale ASR/VAD, accepts retained speech")
  for second in 12..<600 {
   precondition(window.append(voice,now:Double(second+1)))
   precondition(window.samples.count<12*16000)
  }
  precondition(window.totalFrames==600*16000 && window.realtimeRecoveries>50)
  precondition(window.startFrame+window.samples.count==window.totalFrames)
  precondition(window.skippedFrames==window.startFrame)
  print("PASS 10-minute permanently unconfirmed input continues with bounded memory and accurate skip totals")
  window.discardForPause()
  precondition(window.samples.isEmpty)
  precondition(window.append(voice,now:601))
  precondition(window.samples.count==16000)
  print("PASS pause/resume preserves monotonic timeline after recovery")
 }
}
