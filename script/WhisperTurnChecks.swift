import Foundation
@main struct Checks {
 static func main() {
  let chunk=[Float](repeating:0.1,count:512)
  // Multiple turns arriving during one slow decode must retain the first endpoint.
  var turns=WhisperCaptionWindow();turns.usesSilero=true;turns.prioritizesRealtime=true;turns.contextFrames=96000
  precondition(turns.append([Float](repeating:0.1,count:512*150),now:4.8))
  let input=turns.vadInput()!
  turns.applyVAD(start:input.start,probabilities:Array(repeating:0.8,count:40)+Array(repeating:0.05,count:12)+Array(repeating:0.8,count:98),epoch:input.epoch)
  let first=turns.snapshot()!
  precondition(first.isFinal && first.audio.count==40*512+3200)
  precondition(turns.vadEndpointDecodes==1)
  precondition(turns.advance(first,frames:first.audio.count))
  precondition(turns.hasVoice && turns.samples.count==512*150-first.audio.count)
  print("PASS next speaker cannot overwrite an earlier endpoint; later speech is retained")

  var noise=WhisperCaptionWindow();noise.usesSilero=true
  for index in 0..<100 {
   precondition(noise.append(chunk,now:Double(index+1)*0.032))
   let pcm=noise.vadInput()!
   noise.applyVAD(start:pcm.start,probabilities:[0.3],epoch:pcm.epoch)
  }
  precondition(!noise.hasVoice && noise.samples.count<=4800)
  let pcmStart=noise.totalFrames
  for index in 0..<30 {
   precondition(noise.append(chunk,now:4+Double(index)*0.032))
   let pcm=noise.vadInput()!
   noise.applyVAD(start:pcm.start,probabilities:[index==0 ? 0.8 : 0.3],epoch:pcm.epoch)
  }
  precondition(noise.hasVoice && noise.lastVoiceFrame>pcmStart+512*25)
  print("PASS hysteresis rejects moderate background probabilities but sustains established speech")

  var uninterrupted=WhisperCaptionWindow();uninterrupted.usesSilero=true;uninterrupted.prioritizesRealtime=true;uninterrupted.contextFrames=96000
  precondition(uninterrupted.append([Float](repeating:0.1,count:512*220),now:7.04))
  let pcm=uninterrupted.vadInput()!
  uninterrupted.applyVAD(start:pcm.start,probabilities:Array(repeating:0.8,count:220),epoch:pcm.epoch)
  let bounded=uninterrupted.snapshot()!
  precondition(bounded.isFinal && bounded.audio.count==96000 && uninterrupted.boundedWindowDecodes==1)
  uninterrupted.retryAfterNewAudio(bounded)
  precondition(uninterrupted.contextFrames==128000)
  uninterrupted.retryAfterNewAudio(bounded)
  uninterrupted.retryAfterNewAudio(bounded)
  precondition(uninterrupted.contextFrames==160000)
  print("PASS continuous speech closes at 6s without silence; ambiguous retries cap context at 10s")

  var endpoint=WhisperCaptionWindow();endpoint.usesSilero=true
  for index in 0..<40 {
   precondition(endpoint.append(chunk,now:Double(index+1)*0.032))
   let pcm=endpoint.vadInput()!;endpoint.applyVAD(start:pcm.start,probabilities:[0.8],epoch:pcm.epoch)
  }
  let provisional=endpoint.snapshot()!
  precondition(!provisional.isFinal)
  for index in 0..<12 {
   precondition(endpoint.append(chunk,now:1.28+Double(index+1)*0.032))
   let pcm=endpoint.vadInput()!;endpoint.applyVAD(start:pcm.start,probabilities:[0.05],epoch:pcm.epoch)
  }
  let final=endpoint.snapshot()!
  precondition(final.isFinal && final.endFrame==provisional.endFrame)
  precondition(endpoint.snapshot()==nil)
  print("PASS an unchanged preview window can finalize exactly once after its endpoint is detected")
 }
}
