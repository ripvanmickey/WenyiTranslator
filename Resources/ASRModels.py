"""Managed, pinned ASR data downloads. Never installs packages or executes model repository code."""
import argparse,hashlib,json,os,shutil,sys,time,ctypes,threading
from pathlib import Path
CATALOG=json.loads(Path(__file__).with_name('ASRModelCatalog.json').read_text())
PUBLIC=('nemotron','granite','qwen17','qwen06','multitalker')
OUTPUT_LOCK=threading.Lock()
def emit(**x):
 with OUTPUT_LOCK:print(json.dumps(x,ensure_ascii=False),flush=True)
def folder(root,key):
 if key not in (*PUBLIC,'vad'):raise ValueError('未知模型')
 dest=root/'models'/key
 if not dest.resolve().is_relative_to(root.resolve()):raise ValueError('模型目录不能指向外部路径')
 return dest

def state(root,key):
 dest=folder(root,key);mark=dest/'ready.json'
 try:
  manifest=json.loads(mark.read_text())
  if manifest['revision']!=CATALOG[key]['revision'] or not manifest['files']:return None
  for entry in manifest['files']:
   file=(dest/'files'/entry['path']).resolve()
   if not file.is_relative_to((dest/'files').resolve()) or not file.is_file() or file.stat().st_size!=entry['size']:return None
  return manifest
 except (OSError,ValueError,KeyError,TypeError):return None

def checksum(file):
 h=hashlib.sha256()
 with file.open('rb') as f:
  for block in iter(lambda:f.read(4*1024*1024),b''):h.update(block)
 return h.hexdigest()

def complete(root,key,origin):
 dest=folder(root,key);files=dest/'files';entries=[]
 if key=='multitalker':
  weight=files/CATALOG[key]['filename']
  if not weight.is_file() or checksum(weight)!=CATALOG[key]['sha256']:raise ValueError('多人模型校验失败')
 else:
  if not (files/'config.json').is_file():raise ValueError('模型缺少配置文件')
  if not any(files.rglob('*.safetensors')):raise ValueError('模型缺少权重文件')
 for file in sorted(files.rglob('*')):
  if not file.is_file() or '.cache' in file.relative_to(files).parts:continue
  if not file.resolve().is_relative_to(files.resolve()):raise ValueError('模型包含外部文件链接')
  entries.append({'path':str(file.relative_to(files)),'size':file.stat().st_size})
 result=dict(CATALOG[key],files=entries,bytes=sum(x['size'] for x in entries),origin=origin)
 temporary=dest/'ready.tmp';temporary.write_text(json.dumps(result));temporary.replace(dest/'ready.json')
 return result

def download(root,key):
 from huggingface_hub import HfApi,snapshot_download
 from tqdm.auto import tqdm
 class Progress(tqdm):
  def update(self,n=1):
   value=super().update(n)
   emit(type='progress',message='正在下载模型文件',completed=self.n,total=self.total or 0)
   return value
 spec=CATALOG[key];dest=folder(root,key);dest.mkdir(parents=True,exist_ok=True)
 emit(type='progress',message='正在连接下载服务',completed=0,total=0)
 metadata=HfApi().model_info(spec['repo'],revision=spec['revision'],files_metadata=True)
 files=Path(snapshot_download(spec['repo'],revision=spec['revision'],local_dir=str(dest/'files'),tqdm_class=Progress,max_workers=3,allow_patterns=[spec['filename'],'README.md','LICENSE*'] if 'filename' in spec else None))
 # Verify large-file checksums against metadata for the pinned revision, not a mutable latest tag.
 for entry in metadata.siblings or []:
  lfs=getattr(entry,'lfs',None);sha=getattr(lfs,'sha256',None) if lfs else None
  if not sha and isinstance(lfs,dict):sha=lfs.get('sha256')
  if sha:
   if 'filename' in spec and entry.rfilename!=spec['filename']:continue
   path=files/entry.rfilename
   if not path.resolve().is_relative_to(files.resolve()):raise ValueError('下载文件路径无效')
   emit(type='progress',message='正在校验 '+path.name,completed=0,total=0)
   h=hashlib.sha256()
   with path.open('rb') as f:
    for block in iter(lambda:f.read(4*1024*1024),b''):h.update(block)
   if h.hexdigest()!=sha:raise ValueError('模型校验失败，请重新下载')
 return complete(root,key,'download')

def copy_model_file(source,target):
 # APFS copy-on-write avoids duplicating gigabytes during migration; no shared mutable hard links.
 if target.exists():target.unlink()
 try:
  clone=ctypes.CDLL('/usr/lib/libSystem.B.dylib',use_errno=True).clonefile
  clone.argtypes=[ctypes.c_char_p,ctypes.c_char_p,ctypes.c_int]
  if clone(os.fsencode(source),os.fsencode(target),0)==0:return
 except (AttributeError,OSError):pass
 shutil.copy2(source,target)

def import_old(root,key,old):
 from huggingface_hub import snapshot_download
 spec=CATALOG[key]
 if key=='multitalker':
  source=old.parent/'MultitalkerTrial/.runtime/models'/spec['filename'];dest=folder(root,key)/'files';dest.mkdir(parents=True,exist_ok=True);copy_model_file(source,dest/spec['filename']);return complete(root,key,'import')
 source=Path(snapshot_download(spec['repo'],revision=spec['revision'],cache_dir=str(old/'.runtime/models/hub'),local_files_only=True))
 dest=folder(root,key)/'files';dest.mkdir(parents=True,exist_ok=True)
 for file in source.rglob('*'):
  if not file.is_file():continue
  target=dest/file.relative_to(source)
  target.parent.mkdir(parents=True,exist_ok=True)
  copy_model_file(file,target)
 return complete(root,key,'import')

def main():
 p=argparse.ArgumentParser();p.add_argument('action',choices=['list','download','delete','import']);p.add_argument('--root',required=True);p.add_argument('--model',choices=PUBLIC);p.add_argument('--old');a=p.parse_args()
 root=Path(a.root).resolve();root.mkdir(parents=True,exist_ok=True)
 if a.action=='list':
  emit(type='inventory',models={key:state(root,key) for key in PUBLIC});return
 if not a.model:raise ValueError('请选择模型')
 if a.action=='delete':
  dest=folder(root,a.model)
  if dest.is_symlink():raise ValueError('模型目录无效')
  if dest.exists():shutil.rmtree(dest)
 else:
  for key in ([a.model,'vad'] if a.model not in ('granite','multitalker') else [a.model]):
   if state(root,key):continue
   if a.action=='import':
    if not a.old:raise ValueError('未选择旧版模型目录')
    import_old(root,key,Path(a.old))
   else:download(root,key)
 emit(type='done',model=a.model)

if __name__=='__main__':
 try:main()
 except Exception as e:emit(type='error',message=str(e)[:600]);sys.exit(1)
