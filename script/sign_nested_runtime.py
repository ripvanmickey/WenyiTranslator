import sys,subprocess
from pathlib import Path
for p in Path(sys.argv[1]).rglob('*'):
    if not p.is_file() or p.is_symlink() or p.name=='AirTranslate': continue
    with p.open('rb') as f: magic=f.read(4)
    if magic in [b'\xcf\xfa\xed\xfe',b'\xca\xfe\xba\xbe',b'\xfe\xed\xfa\xcf']:
        subprocess.run(['codesign','--force','--timestamp=none','--sign','-',str(p)],check=True)
