#!/usr/bin/env python3
"""Run compact caption sizing and cross-display window-frame regression checks."""
import os
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
manifest = root / "Package.swift"
original = manifest.read_text()
marker = '''                "AirTranslate"
            ]
'''
replacement = '''                "AirTranslate"
            ],
            sources: ["FloatingCaptionCompactSizingTests.swift", "FloatingCaptionWindowFrameVisibilityTests.swift"]
'''
if original.count(marker) != 1:
    raise SystemExit("Cannot locate the test target; Package.swift was not changed")
command = ["xcrun", "swift", "test", "-c", "debug", "--build-system", "native", "--disable-sandbox", "--filter", "FloatingCaptionCompactSizingTests|FloatingCaptionWindowFrameVisibilityTests", *sys.argv[1:]]
try:
    manifest.write_text(original.replace(marker, replacement))
    result = subprocess.run(command, cwd=root, env=os.environ)
finally:
    manifest.write_text(original)
raise SystemExit(result.returncode)
