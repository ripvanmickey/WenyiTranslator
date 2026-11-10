# coding: utf-8
"""Wenyi PCM/JSON bridge. Imports the user's verified, separately installed livecaption."""
import argparse, base64, contextlib, hashlib, json, os, sys, time
from pathlib import Path

OUTPUT=sys.stdout

def emit(value):
    OUTPUT.write(json.dumps(value,ensure_ascii=False)+'\n');OUTPUT.flush()

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--runtime',required=True)
    parser.add_argument('--language',required=True);parser.add_argument('--qwen-model',default='');args=parser.parse_args()
    root=Path(args.runtime);managed=os.environ.get('WENYI_MANAGED_ASR')=='1'
    project=Path(__file__).parent/'ASRProject' if managed else root/'.runtime/project'
    if not managed:
        manifest=json.loads((Path(__file__).with_name('NemotronSourceManifest.json')).read_text())
        for name,digest in manifest['files'].items():
            file=project/name
            if not file.is_file() or hashlib.sha256(file.read_bytes()).hexdigest()!=digest:
                raise RuntimeError('Nemotron运行环境源码与已验证版本不一致：'+name)
    sys.path.insert(0,str(project))
    if managed:
        from ASRModels import state
        key='qwen17' if '1.7B' in args.qwen_model else 'qwen06' if args.qwen_model else 'nemotron'
        if not state(root,key) or not state(root,'vad'):raise RuntimeError('模型文件不完整，请在设置中检查与补齐。')
    # Never let upstream progress messages corrupt the JSON stdout protocol.
    with contextlib.redirect_stdout(sys.stderr):
        import numpy as np
        if managed:
            from livecaption import config
            config.VAD_MODEL=str(root/'models/vad/files')
        if args.qwen_model:
            if args.qwen_model not in ('Qwen/Qwen3-ASR-1.7B','Qwen/Qwen3-ASR-0.6B'):
                raise RuntimeError('不支持的 Qwen ASR 模型')
            from livecaption import config
            config.QWEN_CHUNK_SIZE_SEC=1.0
            config.QWEN_MAX_CONTEXT_SEC=12.0
            config.QWEN_FINALIZATION_MODE='latency'
            config.QWEN_TWO_PASS=False
            config.RULE3_MIN_UTTERANCE_LENGTH=12.0
            from livecaption.asr_qwen import QwenRecognizer
            rec=QwenRecognizer(str(root/('models/qwen17/files' if '1.7B' in args.qwen_model else 'models/qwen06/files')) if managed else args.qwen_model,args.language,diarize=False,word_diarize=False,log=lambda _:None)
        else:
            from livecaption.asr import Recognizer
            rec=Recognizer(str(root/'models/nemotron/files') if managed else 'mlx-community/nemotron-3.5-asr-streaming-0.6b',args.language,diarize=False,log=lambda _:None)
        stream=rec.create_stream()
    emit({'type':'ready'})
    epoch=None;utterance=0;revision=0;start=None;last_text='';last_stats=time.monotonic()
    processed=0;compute=0.0
    for line in sys.stdin:
        if len(line)>262144:raise RuntimeError('Audio packet too large')
        packet=json.loads(line)
        if packet.get('type')!='audio':raise RuntimeError('Invalid audio packet')
        if packet['epoch']!=epoch:
            with contextlib.redirect_stdout(sys.stderr):stream=rec.create_stream()
            epoch=packet['epoch'];utterance=0;revision=0;start=None;last_text=''
        raw=base64.b64decode(packet['pcm'],validate=True)
        if len(raw)%2:raise RuntimeError('Invalid PCM alignment')
        samples=np.frombuffer(raw,dtype='<i2').astype(np.float32)/32768.0
        before=time.perf_counter()
        with contextlib.redirect_stdout(sys.stderr):events=stream.accept_waveform(samples)
        compute+=time.perf_counter()-before;processed+=len(samples)
        for event in events:
            final=event[0]=='final'
            if final:
                text=' '.join(seg[1] for seg in event[1]).strip();span=event[2] if len(event)>2 else len(samples)
            else:
                text=event[1].strip();span=event[3] if len(event)>3 else len(samples)
            if start is None:start=max(0,packet['end_frame']-max(1,int(span)))
            if text and (text!=last_text or final):
                revision+=1
                emit({'type':'text','epoch':epoch,'utterance':utterance,'revision':revision,'final':final,'text':text,
                      'start_frame':start,'end_frame':packet['end_frame'],'end_uptime':packet['end_uptime']})
                last_text=text
            if final:utterance+=1;revision=0;start=None;last_text=''
        if time.monotonic()-last_stats>=2:
            emit({'type':'stats','epoch':epoch,'processed_frames':processed,'end_frame':packet['end_frame'],'compute_seconds':compute})
            last_stats=time.monotonic()
    # Stop/pause is controlled by the app. Do not emit stale final results on shutdown.

if __name__=='__main__':
    try:main()
    except BrokenPipeError:pass
    except Exception as error:
        emit({'type':'error','message':str(error)[:600]});sys.exit(1)
