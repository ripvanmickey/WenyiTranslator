"""Produce a relocatable CPython runtime from verified local installations (no pip at user startup)."""
import argparse, json, os, shutil, subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--python-home',required=True);p.add_argument('--legacy',required=True);p.add_argument('--qwen',required=True);p.add_argument('--granite',required=True);p.add_argument('--output',required=True);a=p.parse_args()
base=Path(a.python_home);out=Path(a.output)
if out.exists():shutil.rmtree(out)
(out/'bin').mkdir(parents=True);(out/'lib').mkdir()
shutil.copy2(base/'bin/python3.12',out/'bin/python3.12')
def ignore(folder,names):
 return [x for x in names if x in ['__pycache__','site-packages','test','tests','idlelib','tkinter','ensurepip'] or x.endswith(('.pyc','.pth'))]
shutil.copytree(base/'lib/python3.12',out/'lib/python3.12',ignore=ignore)
# Some extension modules use the shared interpreter library.
shutil.copy2(base/'lib/libpython3.12.dylib',out/'lib/libpython3.12.dylib')
for name,source in [('legacy',a.legacy),('qwen',a.qwen),('granite',a.granite)]:
 source=Path(source);site=next((source/'lib').glob('python*/site-packages'))
 dest=out/'packages'/name
 shutil.copytree(site,dest,ignore=lambda folder,names:[x for x in names if x=='__pycache__' or x.endswith(('.pyc','.pth')) or x in ['direct_url.json']])
 # Editable project pointers must not escape the app. Project is bundled separately.
 for item in dest.glob('__editable__*'):
  if item.is_dir():shutil.rmtree(item)
  else:item.unlink()
shutil.copy2(out/'packages/legacy/certifi/cacert.pem',out/'cacert.pem')
# Check every native dependency; no build-machine library path may remain.
native=[]
for file in out.rglob('*'):
 if not file.is_file() or file.is_symlink():continue
 magic=file.open('rb').read(4)
 if magic in [b'\xcf\xfa\xed\xfe',b'\xca\xfe\xba\xbe',b'\xfe\xed\xfa\xcf']:
  deps=subprocess.check_output(['otool','-L',str(file)],text=True).splitlines()[1:]
  for dep in deps:
   target=dep.strip().split(' (')[0]
   if target.startswith('/') and not target.startswith(('/usr/lib/','/System/Library/')):
    if target.endswith('/'+file.name) and file.suffix=='.dylib':
     subprocess.run(['install_name_tool','-id','@rpath/'+file.name,str(file)],check=True)
     continue
    candidates=list(file.parent.glob(Path(target).name))
    if not candidates:candidates=list(out.rglob(Path(target).name))
    if not candidates:raise RuntimeError(f'External native dependency: {file}: {target}')
    selected=min(candidates,key=lambda p:len(os.path.relpath(p,file.parent)))
    subprocess.run(['install_name_tool','-change',target,'@loader_path/'+os.path.relpath(selected,file.parent),str(file)],check=True)
  native.append(str(file.relative_to(out)))
(out/'runtime.json').write_text(json.dumps({'python':'3.12','native_files':native,'engines':['legacy','qwen','granite']},indent=2))
print('Bundled',out,'native files:',len(native))
