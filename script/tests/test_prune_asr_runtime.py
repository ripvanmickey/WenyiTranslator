import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from prune_asr_runtime import prune


class PruneRuntimeTests(unittest.TestCase):
    def test_only_approved_regular_files_are_removed_from_staged_app(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            runtime = root / "Wenyi.app" / "Contents" / "Resources" / "ASRRuntime"
            runtime.mkdir(parents=True)
            (runtime / "packages/qwen").mkdir(parents=True)
            legacy = runtime / "packages/legacy"
            removed = {
                "pip/_internal/main.py": b"installer",
                "pip/_vendor/packaging/licenses/_spdx.py": b"lookup code",
                "numpy/_core/tests/test_array.py": b"test",
                "mlx_audio/tts/models/example/README.md": b"guide",
            }
            kept = {
                "pip-25.0.1.dist-info/licenses/LICENSE.txt": b"notice",
                "numpy/_core/tests/COPYING": b"notice",
                "numpy/_core/tests/native.so": b"shared object",
                "numpy/_core/tests/native": bytes.fromhex("cffaedfe"),
                "numpy/_core/tests/manifest-native": b"manifest-listed",
                "numpy/doc/ufuncs.py": b"library code",
                "numpy/testing/__init__.py": b"runtime helpers",
                "scipy/special/tests/test_hyp2f1.py": b"referenced by SciPy",
                "transformers/tests/test_retained.py": b"unreviewed dependency",
                "mlx_audio/tts/models/example/config.json": b"runtime data",
            }
            for relative, data in (removed | kept).items():
                path = legacy / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(data)
            (runtime / "runtime.json").write_text(json.dumps({
                "native_files": ["packages/legacy/numpy/_core/tests/manifest-native"]
            }))
            outside = root / "external"
            outside.mkdir()
            expected = outside / "test_external.py"
            expected.write_text("outside the app")
            (legacy / "numpy/tests").symlink_to(outside, target_is_directory=True)
            (legacy / "numpy/_core/tests/symlink").symlink_to(expected)

            plan = prune(runtime)
            self.assertFalse(plan["applied"])
            self.assertEqual(set(plan["paths"]), {f"packages/legacy/{name}" for name in removed})
            self.assertTrue(all((legacy / name).is_file() for name in removed))
            self.assertEqual(prune(runtime, apply=True)["paths"], plan["paths"])
            self.assertTrue(all(not (legacy / name).exists() for name in removed))
            self.assertFalse((legacy / "pip").exists())
            for name, data in kept.items():
                self.assertEqual((legacy / name).read_bytes(), data)
            self.assertEqual(expected.read_text(), "outside the app")
            self.assertTrue((legacy / "numpy/_core/tests/symlink").is_symlink())
            self.assertEqual(prune(runtime, apply=True)["paths"], [])

    def test_rejects_unstaged_source_runtime(self):
        with tempfile.TemporaryDirectory() as temporary:
            runtime = Path(temporary) / "Resources/ASRRuntime"
            runtime.mkdir(parents=True)
            with self.assertRaises(ValueError):
                prune(runtime, apply=True)
