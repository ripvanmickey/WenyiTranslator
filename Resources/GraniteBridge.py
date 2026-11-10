"""Granite chunked ASR adapter. This is not native incremental audio decoding."""
import argparse,base64,contextlib,json,os,sys,time
from pathlib import Path
OUT=sys.stdout

def emit(value):OUT.write(json.dumps(value,ensure_ascii=False)+'\n');OUT.flush()

class Window:
 def __init__(self,np):self.np=np;self.clear()
 def clear(self):self.blocks=[];self.count=0;self.quiet=0;self.decoded=0;self.pre=self.np.empty(0,dtype=self.np.float32)
 def accept(self,a):
  audible=float(self.np.sqrt(self.np.mean(a*a)))>=0.004
  if not self.blocks and not audible:
   self.pre=self.np.concatenate([self.pre,a])[-3200:];return None
  if not self.blocks and len(self.pre):a=self.np.concatenate([self.pre,a]);self.pre=self.np.empty(0,dtype=self.np.float32)
  self.blocks.append(a.copy());self.count+=len(a);self.quiet=0 if audible else self.quiet+len(a)
  final=(self.quiet>=12800 and self.count>=8000) or self.count>=192000
  if not final and not(self.count>=64000 and self.count-self.decoded>=32000):return None
  self.decoded=self.count
  return self.np.concatenate(self.blocks),final,self.count

def main():
 p=argparse.ArgumentParser();p.add_argument('--runtime',required=True);p.add_argument('--language',required=True);args=p.parse_args()
 languages={'en':'English','ja':'Japanese','fr':'French','de':'German','es':'Spanish','pt':'Portuguese'}
 language=languages.get(args.language.lower().split('-')[0])
 if not language:raise RuntimeError('Granite 当前接入支持英语、日语、法语、德语、西班牙语和葡萄牙语。')
 root=Path(args.runtime)
 if os.environ.get('WENYI_MANAGED_ASR')=='1':
  from ASRModels import state
  if not state(root,'granite'):raise RuntimeError('模型文件不完整，请在设置中检查与补齐。')
 with contextlib.redirect_stdout(sys.stderr):
  import numpy as np
  from mlx_audio.stt.utils import load_model
  model=load_model(str(root/'models/granite/files') if os.environ.get('WENYI_MANAGED_ASR')=='1' else 'ibm-granite/granite-speech-5.0-2b')
 emit({'type':'ready'});window=Window(np);epoch=None;utt=0;rev=0;previous='';compute=0.;processed=0
 for line in sys.stdin:
  if len(line)>262144:raise RuntimeError('Audio packet too large')
  packet=json.loads(line)
  if packet.get('type')!='audio':raise RuntimeError('Invalid audio packet')
  if packet['epoch']!=epoch:epoch=packet['epoch'];window.clear();utt=0;rev=0;previous=''
  raw=base64.b64decode(packet['pcm'],validate=True)
  if len(raw)%2:raise RuntimeError('Invalid PCM alignment')
  a=np.frombuffer(raw,dtype='<i2').astype(np.float32)/32768.
  if not len(a):continue
  processed+=len(a);job=window.accept(a)
  if job is None:continue
  audio,final,span=job;start=time.perf_counter()
  with contextlib.redirect_stdout(sys.stderr):
   punctuation=' For Japanese, use Japanese punctuation: 、 for clauses, 。 for complete sentences, and ？ for questions. Preserve every spoken word; do not summarize or add explanations.' if language=='Japanese' else ''
   result=model.generate(audio,max_tokens=256,temperature=0.,prompt=f'The speech is in {language}. Transcribe it exactly; do not translate. Transcribe the speech with proper punctuation and capitalization.'+punctuation,verbose=False)
  compute+=time.perf_counter()-start;text=result.text.strip()
  if text and (text!=previous or final):
   rev+=1
   emit({'type':'text','epoch':epoch,'utterance':utt,'revision':rev,'final':final,'text':text,'start_frame':max(0,packet['end_frame']-span),'end_frame':packet['end_frame'],'end_uptime':packet['end_uptime']})
   previous=text
  emit({'type':'stats','epoch':epoch,'processed_frames':processed,'end_frame':packet['end_frame'],'compute_seconds':compute})
  if final:window.clear();utt+=1;rev=0;previous=''

if __name__=='__main__':
 try:main()
 except BrokenPipeError:pass
 except Exception as error:emit({'type':'error','message':str(error)[:600]});sys.exit(1)
