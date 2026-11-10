import Foundation
import AVFoundation
struct LanguageOption: Sendable { let id: String }
final class Recorder: @unchecked Sendable {
 let lock=NSLock(); var ids:[String]=[];var finals:[Bool]=[];var failures=0
 func add(_ metadata:AppleSpeechRecognitionMetadata){lock.withLock{ids.append(metadata.segmentID);finals.append(metadata.isFinal)}}
 func fail(){lock.withLock{failures+=1}}
 var count:Int {lock.withLock{ids.count}}
}
@main struct Checks {
 @MainActor static func main() async throws {
  DispatchQueue.global().asyncAfter(deadline: .now()+25) { _exit(124) }
  let root=URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent("wenyi-nemotron-check-"+UUID().uuidString)
  let fm=FileManager.default
  try fm.createDirectory(at:root.appendingPathComponent(".runtime/env/bin"),withIntermediateDirectories:true)
  try fm.createDirectory(at:root.appendingPathComponent(".runtime/project/livecaption"),withIntermediateDirectories:true)
  try fm.createSymbolicLink(atPath:root.appendingPathComponent(".runtime/env/bin/python").path,withDestinationPath:URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("work/AirTranslate-1.16.0/Resources/ASRRuntime/bin/python3.12").path)
  try "# fixture".write(to:root.appendingPathComponent(".runtime/project/livecaption/asr.py"),atomically:true,encoding:.utf8)
  defer { try? fm.removeItem(at: root) }
  let packagedRuntime=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("work/AirTranslate-1.16.0/Resources/ASRRuntime")
  let fixtureRuntime=root.appendingPathComponent("ASRRuntime")
  try fm.createDirectory(at:fixtureRuntime.appendingPathComponent("bin"),withIntermediateDirectories:true)
  try fm.createSymbolicLink(at:fixtureRuntime.appendingPathComponent("bin/python3.12"),withDestinationURL:packagedRuntime.appendingPathComponent("bin/python3.12"))
  for part in ["lib","packages"] { try fm.createSymbolicLink(at:fixtureRuntime.appendingPathComponent(part),withDestinationURL:packagedRuntime.appendingPathComponent(part)) }
  let modelData=root.appendingPathComponent("managed")
  for key in ["nemotron","vad","qwen17","granite","multitalker"] {
   let folder=modelData.appendingPathComponent("models/"+key)
   try fm.createDirectory(at:folder.appendingPathComponent("files"),withIntermediateDirectories:true)
   try "{}".write(to:folder.appendingPathComponent("ready.json"),atomically:true,encoding:.utf8)
   try "{}".write(to:folder.appendingPathComponent("files/config.json"),atomically:true,encoding:.utf8)
   if key=="multitalker" { try Data().write(to:folder.appendingPathComponent("files/multitalker-parakeet-streaming-0.6b-v1-Q8_0.gguf")) }
  }
  let script = #"""
import sys,json,time
language=sys.argv[sys.argv.index('--language')+1]
if language=='en-slow': time.sleep(5)
print(json.dumps({'type':'ready'}),flush=True)
if language=='en-block': time.sleep(60)
if language=='en-crash': time.sleep(0.1);sys.exit(3)
epoch=None;counter=0
for line in sys.stdin:
 p=json.loads(line)
 if p['epoch']!=epoch: epoch=p['epoch'];counter=0
 counter+=1
 msg={'type':'text','text':'hello' if counter%2 else 'hello world','epoch':epoch,'utterance':(counter-1)//2,'revision':1 if counter%2 else 2,'final':counter%2==0,'start_frame':max(0,p['end_frame']-640),'end_frame':p['end_frame'],'end_uptime':p['end_uptime']}
 encoded=json.dumps(msg)+'\n'
 sys.stdout.write(encoded[:8]);sys.stdout.flush();time.sleep(.005)
 sys.stdout.write(encoded[8:]);sys.stdout.flush()
"""#
  try script.write(to:root.appendingPathComponent("NemotronBridge.py"),atomically:true,encoding:.utf8)
  try fm.createDirectory(at:root.appendingPathComponent(".runtime/qwen-env/bin"),withIntermediateDirectories:true)
  try fm.createSymbolicLink(atPath:root.appendingPathComponent(".runtime/qwen-env/bin/python").path,withDestinationPath:root.appendingPathComponent(".runtime/env/bin/python").path)
  try "{}".write(to:root.appendingPathComponent(".runtime/qwen-ready.json"),atomically:true,encoding:.utf8)
  let format=AVAudioFormat(commonFormat:.pcmFormatInt16,sampleRate:16000,channels:1,interleaved:true)!
  let pcm=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:320)!;pcm.frameLength=320
  for i in 0..<320 {pcm.int16ChannelData![0][i]=8192}
  let sample=CoreAudioTapCapture.sampleBuffer(pcm.audioBufferList,format:format.streamDescription.pointee)!
  let recorder=Recorder();let transcriber=NemotronSpeechTranscriber(resources:root,modelData:modelData)
  try await transcriber.start(folder:root.path,language:.init(id:"en-US"),update:{_,meta in recorder.add(meta)},recovery:nil,failure:{_ in recorder.fail()})
  transcriber.append(sample);transcriber.append(sample)
  for _ in 0..<100 {if recorder.count>=2{break};try await Task.sleep(for:.milliseconds(20))}
  precondition(recorder.count==2)
  precondition(recorder.lock.withLock{recorder.ids[0]==recorder.ids[1] && recorder.finals == [false,true]})
  transcriber.setPaused(true);transcriber.append(sample);try await Task.sleep(for:.milliseconds(100));precondition(recorder.count==2)
  transcriber.setPaused(false);transcriber.append(sample);transcriber.append(sample)
  for _ in 0..<100 {if recorder.count>=4{break};try await Task.sleep(for:.milliseconds(20))}
  precondition(recorder.count==4 && recorder.lock.withLock{recorder.ids[2] != recorder.ids[0]})
  transcriber.stop()
  try await transcriber.start(folder:root.path,language:.init(id:"en-US"),update:{_,meta in recorder.add(meta)},recovery:nil,failure:{_ in recorder.fail()})
  transcriber.append(sample);transcriber.append(sample)
  for _ in 0..<100 {if recorder.count>=6{break};try await Task.sleep(for:.milliseconds(20))}
  precondition(recorder.count==6 && recorder.lock.withLock{recorder.ids[4] != recorder.ids[0]})
  transcriber.stop()
  print("PASS process bridge: fragmented JSON, ordered partial/final identity, pause/resume epochs")
  let slow=NemotronSpeechTranscriber(resources:root,modelData:modelData)
  let startup=Task {try await slow.start(folder:root.path,language:.init(id:"en-slow"),update:{_,_ in},recovery:nil,failure:{_ in})}
  try await Task.sleep(for:.milliseconds(50));slow.stop()
  do {try await startup.value;fatalError("Cancelled startup succeeded")} catch is CancellationError {}
  print("PASS startup cancellation resolves without hanging")
  let blocked=NemotronSpeechTranscriber(resources:root,modelData:modelData)
  try await blocked.start(folder:root.path,language:.init(id:"en-block"),update:{_,_ in},recovery:nil,failure:{_ in})
  for _ in 0..<1000 {blocked.append(sample)}
  precondition(!blocked.diagnosticsSummary().contains("音频队列恢复 0 次"))
  blocked.stop();try await Task.sleep(for:.milliseconds(100))
  print("PASS blocked child: bounded queue recovery; broken-pipe stop does not kill app")
  let crash=NemotronSpeechTranscriber(resources:root,modelData:modelData);let errors=Recorder()
  try await crash.start(folder:root.path,language:.init(id:"en-crash"),update:{_,_ in},recovery:nil,failure:{_ in errors.fail()})
  try await Task.sleep(for:.milliseconds(400))
  precondition(errors.lock.withLock{errors.failures==1});crash.stop()
  print("PASS child crash becomes one recoverable failure")
  let qwen=NemotronSpeechTranscriber(resources:root,qwenModel:"Qwen/Qwen3-ASR-1.7B",modelData:modelData);let qrec=Recorder()
  try await qwen.start(folder:root.path,language:.init(id:"ja-JP"),update:{_,meta in qrec.add(meta)},recovery:nil,failure:{_ in qrec.fail()})
  qwen.append(sample);qwen.append(sample)
  for _ in 0..<100 {if qrec.count>=2{break};try await Task.sleep(for:.milliseconds(20))}
  precondition(qrec.count==2 && qwen.diagnosticsSummary().contains("Qwen3-ASR"));qwen.stop()
  print("PASS Qwen environment selection, process startup and subtitle delivery")
  let mn=root.appendingPathComponent("NemotronTrial")
  try fm.createDirectory(at:mn.appendingPathComponent(".runtime/env/bin"),withIntermediateDirectories:true)
  try fm.createDirectory(at:mn.appendingPathComponent(".runtime/project/livecaption"),withIntermediateDirectories:true)
  try fm.createSymbolicLink(atPath:mn.appendingPathComponent(".runtime/env/bin/python").path,withDestinationPath:root.appendingPathComponent(".runtime/env/bin/python").path)
  try "# fixture".write(to:mn.appendingPathComponent(".runtime/project/livecaption/asr.py"),atomically:true,encoding:.utf8)
  let mm=root.appendingPathComponent("MultitalkerTrial/.runtime/models")
  try fm.createDirectory(at:mm,withIntermediateDirectories:true)
  try Data().write(to:mm.appendingPathComponent("multitalker-parakeet-streaming-0.6b-v1-Q8_0.gguf"))
  try script.write(to:root.appendingPathComponent("MultitalkerBridge.py"),atomically:true,encoding:.utf8)
  let multi=NemotronSpeechTranscriber(resources:root,multitalker:true,modelData:modelData);let mr=Recorder()
  try await multi.start(folder:mn.path,language:.init(id:"en-US"),update:{_,meta in mr.add(meta)},recovery:nil,failure:{_ in mr.fail()})
  multi.append(sample);multi.append(sample)
  for _ in 0..<100 {if mr.count>=2{break};try await Task.sleep(for:.milliseconds(20))}
  precondition(mr.count==2 && multi.diagnosticsSummary().contains("Multitalker Parakeet"));multi.stop()
  print("PASS Multitalker runtime routing, process startup and paragraph revisions")
  try fm.createDirectory(at:root.appendingPathComponent(".runtime/granite-env/bin"),withIntermediateDirectories:true)
  try fm.createSymbolicLink(atPath:root.appendingPathComponent(".runtime/granite-env/bin/python").path,withDestinationPath:root.appendingPathComponent(".runtime/env/bin/python").path)
  try "{}".write(to:root.appendingPathComponent(".runtime/granite-ready.json"),atomically:true,encoding:.utf8)
  try script.write(to:root.appendingPathComponent("GraniteBridge.py"),atomically:true,encoding:.utf8)
  let granite=NemotronSpeechTranscriber(resources:root,granite:true,modelData:modelData);let gr=Recorder()
  try await granite.start(folder:root.path,language:.init(id:"ja-JP"),update:{_,meta in gr.add(meta)},recovery:nil,failure:{_ in gr.fail()})
  granite.append(sample);granite.append(sample)
  for _ in 0..<100 {if gr.count>=2{break};try await Task.sleep(for:.milliseconds(20))}
  precondition(gr.count==2 && granite.diagnosticsSummary().contains("Granite Speech"));granite.stop()
  print("PASS Granite isolated environment, Japanese startup and subtitle revisions")


 }
}
