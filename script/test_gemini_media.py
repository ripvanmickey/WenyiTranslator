#!/usr/bin/env python3
"""Run Gemini protocol, media and paragraph suites without unrelated Apple SDK tests.

The app still builds for the package's macOS 14 floor. Restore Package.swift even
when compilation or tests fail. Do not run other SwiftPM jobs against this package
concurrently with this focused check.
"""
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
            sources: ["MediaWorkspaceTests.swift", "GeminiLiveTranslationServiceTests.swift", "GeminiVideoTranscriptionTests.swift", "RealtimeTranslationParagraphsTests.swift", "RealtimeTestSupport.swift"]
'''
if original.count(marker) != 1:
    raise SystemExit("Cannot locate the test target; Package.swift was not changed")
command = ["xcrun", "swift", "test", "-c", "debug", "--build-system", "native", "--disable-sandbox", "--filter", "MediaWorkspaceTests|GeminiLiveTranslationServiceTests|GeminiVideoTranscriptionTests|RealtimeTranslationParagraphsTests", *sys.argv[1:]]
try:
    manifest.write_text(original.replace(marker, replacement))
    result = subprocess.run(command, cwd=root, env=os.environ)
finally:
    manifest.write_text(original)
raise SystemExit(result.returncode)
