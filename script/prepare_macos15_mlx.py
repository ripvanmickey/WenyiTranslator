import json,urllib.request,hashlib,zipfile,shutil,subprocess
from pathlib import Path
root=Path(__file__).resolve().parent.parent
base=root/'Resources/ASRRuntime/packages';cache=root.parent/'macos15-wheels';cache.mkdir(exist_ok=True)
manifest=[]
for profile,version in [('legacy','0.31.2'),('granite','0.32.4')]:
 dest=base/profile
 for project in ['mlx','mlx-metal']:
  data=json.load(urllib.request.urlopen(f'https://pypi.org/pypi/{project}/{version}/json'))
  f=next(x for x in data['urls'] if 'macosx_15_0_arm64' in x['filename'] and ('cp312' in x['filename'] or 'py3-none' in x['filename']))
  p=cache/f['filename']
  if not p.exists(): urllib.request.urlretrieve(f['url'],p)
  assert hashlib.sha256(p.read_bytes()).hexdigest()==f['digests']['sha256']
  if project=='mlx':
   shutil.rmtree(dest/'mlx')
   for old in dest.glob('mlx-*.dist-info'):shutil.rmtree(old)
  else:
   for old in dest.glob('mlx_metal-*.dist-info'):shutil.rmtree(old)
  with zipfile.ZipFile(p) as z:
   for item in z.infolist():
    parts=Path(item.filename).parts
    assert not item.filename.startswith('/') and '..' not in parts
   z.extractall(dest)
  manifest.append({'profile':profile,'filename':p.name,'url':f['url'],'sha256':f['digests']['sha256']})
  print('Verified and installed',p.name,flush=True)
(base.parent/'macos15-wheels.json').write_text(json.dumps(manifest,indent=2))
# Regenerate native list for the new wheels; their signing is done in the package step.
root=base.parent;native=[]
for p in root.rglob('*'):
 if p.is_file() and not p.is_symlink():
  with p.open('rb') as h:magic=h.read(4)
  if magic in [b'\xcf\xfa\xed\xfe',b'\xca\xfe\xba\xbe',b'\xfe\xed\xfa\xcf']:native.append(str(p.relative_to(root)))
manifest=json.loads((root/'runtime.json').read_text());manifest['native_files']=native;manifest['minimum_macos']='15.0'
(root/'runtime.json').write_text(json.dumps(manifest,indent=2))
