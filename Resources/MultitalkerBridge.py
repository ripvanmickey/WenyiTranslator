"""Live single-stream drafts + true multitalker paragraph confirmation.
The upstream public streaming API is single-speaker; do not pass diarize=on to it.
"""
import argparse, base64, contextlib, json, os, sys, time
from pathlib import Path
OUTPUT=sys.stdout

def emit(value):
 OUTPUT.write(json.dumps(value,ensure_ascii=False)+'\n');OUTPUT.flush()

class ParagraphEngine:
 def __init__(self, model, api, np):
  self.model=model;self.api=api;self.np=np
  self.session=model.session(n_threads=4)
  self.stream=None;self.audio=[];self.samples=0;self.quiet=0;self.voice=0
  self.text='';self.preroll=np.empty(0,dtype=np.float32);self.starts=0;self.utterance=0;self.revision=0
 def reset(self):
  if self.stream is not None:self.stream.reset()
  self.stream=None;self.audio=[];self.samples=0;self.quiet=0;self.voice=0;self.text='';self.revision=0;self.preroll=self.np.empty(0,dtype=self.np.float32)
 def accept(self,samples):
  if len(samples)==0:return []
  rms=float(self.np.sqrt(self.np.mean(samples*samples)))
  # Energy is used only to find quiet endpoints, not to reject active audio.
  audible=rms>=0.004
  if self.stream is None:
   if not audible:
    self.preroll=self.np.concatenate([self.preroll,samples])[-3200:]
    return []
   if len(self.preroll):samples=self.np.concatenate([self.preroll,samples]);self.preroll=self.np.empty(0,dtype=self.np.float32)
   self.stream=self.session.stream(language='en',diarize='off',family=self.api.ParakeetStreamOptions(att_context_right=6))
  self.audio.append(samples.copy());self.samples+=len(samples)
  self.voice+=len(samples) if audible else 0
  self.quiet=0 if audible else self.quiet+len(samples)
  self.stream.feed(samples)
  current=self.stream.text().full.strip();events=[]
  if current and current!=self.text:
   self.text=current;self.revision+=1
   events.append((False,current,self.utterance,self.revision,self.samples))
  if (self.quiet>=12800 and self.samples>=16000) or self.samples>=192000:
   self.stream.finalize();draft=self.stream.text().full.strip()
   self.stream.reset();self.stream=None
   audio=self.np.concatenate(self.audio)
   # Same resident model. Streaming lease must be released before multitalker run.
   result=self.session.run(audio,language='en',diarize='on',timestamps='segment')
   parts=[]
   for seg in result.segments:
    text=seg.text.strip()
    if not text:continue
    label=f'[说话人 {seg.speaker_id}] ' if seg.speaker_id>0 else ''
    parts.append(label+text)
   final='\n'.join(parts).strip() or result.text.strip() or draft
   if final:
    self.revision+=1
    events.append((True,final,self.utterance,self.revision,self.samples))
   self.utterance+=1;self.reset()
  return events
 def close(self):
  self.reset();self.session.close()

def main():
 parser=argparse.ArgumentParser();parser.add_argument('--runtime',required=True);parser.add_argument('--language',required=True)
 args=parser.parse_args()
 if args.language.lower() not in ('en','en-us','en-gb','en-au'):
  raise RuntimeError('Multitalker Parakeet 仅支持英语，请选择英语或切回其他引擎。')
 root=Path(args.runtime)
 if os.environ.get('WENYI_MANAGED_ASR')=='1':
  from ASRModels import state
  if not state(root,'multitalker'):raise RuntimeError('模型文件不完整，请在设置中检查与补齐。')
 resources=Path(__file__).parent/'MultitalkerNative'
 os.environ['TRANSCRIBE_LIBRARY']=str(resources/'libtranscribe.dylib')
 sys.path.insert(0,str(resources/'python'))
 with contextlib.redirect_stdout(sys.stderr):
  import numpy as np
  import transcribe_cpp as api
  weight=root/'models/multitalker/files/multitalker-parakeet-streaming-0.6b-v1-Q8_0.gguf' if os.environ.get('WENYI_MANAGED_ASR')=='1' else root/'.runtime/models/multitalker-parakeet-streaming-0.6b-v1-Q8_0.gguf'
  model=api.Model(str(weight),backend='metal')
  if not model.supports('diarization'):raise RuntimeError('该模型包不支持多人识别，请重新准备试用模型。')
  engine=ParagraphEngine(model,api,np)
 emit({'type':'ready'})
 epoch=None;compute=0.;processed=0;laststats=time.monotonic();starts={}
 try:
  for line in sys.stdin:
   if len(line)>262144:raise RuntimeError('Audio packet too large')
   packet=json.loads(line)
   if packet.get('type')!='audio':raise RuntimeError('Invalid audio packet')
   if packet['epoch']!=epoch:
    engine.close();engine=ParagraphEngine(model,api,np);epoch=packet['epoch'];starts={}
   raw=base64.b64decode(packet['pcm'],validate=True)
   if len(raw)%2:raise RuntimeError('Invalid PCM alignment')
   samples=np.frombuffer(raw,dtype='<i2').astype(np.float32)/32768.
   before=time.perf_counter()
   with contextlib.redirect_stdout(sys.stderr):events=engine.accept(samples)
   compute+=time.perf_counter()-before;processed+=len(samples)
   for final,text,utt,rev,span in events:
    start=starts.setdefault(utt,max(0,packet['end_frame']-span))
    emit({'type':'text','epoch':epoch,'utterance':utt,'revision':rev,'final':final,'text':text,
          'start_frame':start,'end_frame':packet['end_frame'],'end_uptime':packet['end_uptime']})
    if final:starts.pop(utt,None)
   if time.monotonic()-laststats>=2:
    emit({'type':'stats','epoch':epoch,'processed_frames':processed,'end_frame':packet['end_frame'],'compute_seconds':compute})
    laststats=time.monotonic()
 finally:
  with contextlib.redirect_stdout(sys.stderr):engine.close();model.close()

if __name__=='__main__':
 try:main()
 except BrokenPipeError:pass
 except Exception as error:emit({'type':'error','message':str(error)[:600]});sys.exit(1)
