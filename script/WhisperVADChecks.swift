import Foundation
@main struct Checks {
 static func main() {
  let chunk=[Float](repeating:0.1,count:512)
  var window=WhisperCaptionWindow();window.usesSilero=true
  for index in 0..<9375 {
   precondition(window.append(chunk,now:Double(index+1)*0.032))
   let input=window.vadInput()!
   window.applyVAD(start:input.start,probabilities:[0.01],epoch:input.epoch)
   precondition(window.samples.count<=4800)
   precondition(window.snapshot()==nil)
  }
  precondition(window.nonSpeechReleasedFrames>16000*299)
  print("PASS 300s non-speech cannot fill buffer even when energy is high")
  var speech=WhisperCaptionWindow();speech.usesSilero=true
  for index in 0..<100 {
   precondition(speech.append(chunk,now:Double(index+1)*0.032))
   let input=speech.vadInput()!
   speech.applyVAD(start:input.start,probabilities:[index<50 ? 0.01 : 0.8],epoch:input.epoch)
  }
  precondition(speech.hasVoice && speech.startFrame <= 50*512-4800)
  let before=speech.startFrame
  let pending=speech.snapshot()!
  speech.retryAfterNewAudio(pending)
  for index in 0..<100 {
   precondition(speech.append(chunk,now:3.2+Double(index+1)*0.032))
   let input=speech.vadInput()!
   speech.applyVAD(start:input.start,probabilities:[0.01],epoch:input.epoch)
  }
  precondition(speech.startFrame==before,"Unrecognized speech must not be discarded by subsequent silence")
  precondition(speech.snapshot()!.isFinal)
  let stale=speech.vadInput()
  speech.discardForPause()
  precondition(speech.append(chunk,now:7))
  let fresh=speech.vadInput()!
  speech.applyVAD(start:fresh.start,probabilities:[0.9],epoch:fresh.epoch-1)
  precondition(!speech.hasVoice)
  speech.applyVAD(start:fresh.start,probabilities:[0.9],epoch:fresh.epoch)
  precondition(speech.hasVoice)
  _=stale
  print("PASS onset padding, silence endpoint, unresolved speech retention, stale pause rejection")
 }
}
