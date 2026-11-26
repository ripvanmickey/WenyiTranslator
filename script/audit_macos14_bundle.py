"""Audit declared macOS floor, arm64 slices and relocatable native dependencies."""
import sys,subprocess,re,json,plistlib
from pathlib import Path
app=Path(sys.argv[1]).resolve();root=app/'Contents';files=[];failures=[]
info=plistlib.loads((root/'Info.plist').read_bytes())
assert info['LSMinimumSystemVersion']=='14.0',info.get('LSMinimumSystemVersion')
for p in root.rglob('*'):
 if not p.is_file() or p.is_symlink():continue
 with p.open('rb') as f:magic=f.read(4)
 if magic not in [b'\xcf\xfa\xed\xfe',b'\xca\xfe\xba\xbe',b'\xfe\xed\xfa\xcf']:continue
 out=subprocess.check_output(['otool','-l',str(p)],text=True)
 versions=re.findall(r'\bminos\s+([\d.]+)',out)+re.findall(r'cmd LC_VERSION_MIN_MACOSX\s+cmdsize \d+\s+version ([\d.]+)',out)
 arch=subprocess.check_output(['lipo','-archs',str(p)],text=True).strip()
 if 'arm64' not in arch:failures.append(f'No arm64: {p}')
 if not versions or any(tuple((list(map(int,v.split('.')))+[0,0])[:3])>(14,0,0) for v in versions):failures.append(f'OS requirement: {p} {versions}')
 for line in subprocess.check_output(['otool','-L',str(p)],text=True).splitlines()[1:]:
  if not line.startswith('\t'): continue
  dep=line.strip().split(' (')[0]
  if dep.startswith('/') and not dep.startswith(('/usr/lib/','/System/Library/')):failures.append(f'Absolute dependency: {p}: {dep}')
 files.append({'file':str(p.relative_to(app)),'architectures':arch,'minimum_macos':versions})
main_loads=subprocess.check_output(['otool','-l',str(root/'MacOS/AirTranslate')],text=True)
# The linked SDK controls system UI compatibility independently of the minimum OS.
# Never distribute a binary whose SDK was accidentally replaced by the 14.0 floor.
expected_sdk=subprocess.check_output(['xcrun','--sdk','macosx','--show-sdk-version'],text=True).strip()
sdk_match=re.search(r'cmd LC_BUILD_VERSION\s+cmdsize \d+\s+platform \d+\s+minos [\d.]+\s+sdk ([\d.]+)',main_loads)
linked_sdk=sdk_match.group(1) if sdk_match else None
if linked_sdk!=expected_sdk:failures.append(f'Executable SDK: expected {expected_sdk}, found {linked_sdk}')
for block in main_loads.split('Load command'):
 if 'Translation.framework' in block and 'LC_LOAD_WEAK_DYLIB' not in block: failures.append('Translation framework must be weak-linked for macOS14')
print(json.dumps({'build':info['CFBundleVersion'],'native_count':len(files),'expected_sdk':expected_sdk,'linked_sdk':linked_sdk,'failures':failures,'files':files},indent=2))
assert not failures,failures
