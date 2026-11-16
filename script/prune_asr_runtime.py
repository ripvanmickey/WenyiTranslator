"""Remove build-only files from an app's staged Python runtime before signing."""

import argparse
from collections import Counter
import json
import os
from pathlib import Path
import stat

TEST_PACKAGES = {"fsspec", "mlx_audio", "numpy", "regex", "scipy"}
RETAINED_TESTS = {("scipy", "special", "tests")}  # Referenced by SciPy's _precompute helper.
LICENSE_PREFIXES = ("license", "licence", "copying", "copyright", "notice", "authors",
                    "credits", "third_party", "third-party", "patents", "attribution")
NATIVE_SUFFIXES = {".so", ".dylib", ".metallib", ".a"}
NATIVE_MAGICS = {bytes.fromhex(x) for x in (
    "feedface", "cefaedfe", "feedfacf", "cffaedfe", "cafebabe", "bebafeca", "cafebabf", "bfbafeca"
)}


def removal_category(parts):
    # These are pip's vendored SPDX lookup modules, distinct from license notices.
    if parts[:4] == ("pip", "_vendor", "packaging", "licenses") and parts[4:] in {("__init__.py",), ("_spdx.py",)}:
        return "pip"
    # Preserve distribution metadata and license notices even inside a selected tree.
    if any(part.endswith((".dist-info", ".egg-info")) or part.lower().startswith(LICENSE_PREFIXES)
           for part in parts):
        return None
    if parts[0] == "pip":
        return "pip"
    if parts[0] in TEST_PACKAGES and "tests" in parts[1:-1]:
        prefix = parts[:parts.index("tests") + 1]
        return None if prefix in RETAINED_TESTS else "tests"
    if parts in {("mlx", "include", "metal_cpp", "README.md"), ("numpy", "ma", "README.rst")}:
        return "docs"
    if len(parts) == 5 and parts[:3] == ("mlx_audio", "tts", "models") and parts[-1] == "README.md":
        return "docs"
    return None


def prune(runtime, *, apply=False):
    runtime = runtime.absolute()
    if (runtime.name, runtime.parent.name, runtime.parent.parent.name) != ("ASRRuntime", "Resources", "Contents"):
        raise ValueError("Expected a staged .app/Contents/Resources/ASRRuntime")
    app = runtime.parents[2]
    if app.suffix != ".app" or any(p.is_symlink() for p in (runtime, *tuple(runtime.parents)[:3])):
        raise ValueError("The staged app and runtime must be real directories")
    manifest = json.loads((runtime / "runtime.json").read_text())
    native_files = set(manifest["native_files"])
    planned = []
    for profile in ("legacy", "qwen"):
        root = runtime / "packages" / profile
        if root.is_symlink() or root.parent.is_symlink() or not root.is_dir():
            raise ValueError(f"Invalid runtime profile: {profile}")
        for folder, dirs, names in os.walk(root, followlinks=False):
            dirs.sort()
            for name in sorted(names):
                path = Path(folder) / name
                category = removal_category(path.relative_to(root).parts)
                if not category or path.relative_to(runtime).as_posix() in native_files:
                    continue
                metadata = path.lstat()
                if not stat.S_ISREG(metadata.st_mode) or path.suffix.lower() in NATIVE_SUFFIXES:
                    continue
                with path.open("rb") as handle:
                    if handle.read(4) in NATIVE_MAGICS:
                        continue
                planned.append((path, category, metadata.st_size))
    counts, sizes = Counter(), Counter()
    for path, category, size in planned:
        counts[category] += 1
        sizes[category] += size
        if apply:
            path.unlink()
    if apply:
        # Removing empty parents stops pip from appearing as an importable namespace package.
        for path in sorted({ancestor for file, _, _ in planned for ancestor in file.parents
                            if ancestor.is_relative_to(runtime / "packages")},
                           key=lambda path: len(path.parts), reverse=True):
            if path.is_dir() and not any(path.iterdir()):
                path.rmdir()
    return {
        "applied": apply,
        "files_by_category": dict(counts),
        "bytes_by_category": dict(sizes),
        "paths": [path.relative_to(runtime).as_posix() for path, _, _ in planned],
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("runtime", type=Path)
    parser.add_argument("--apply", action="store_true", help="Remove the listed files from the staged copy")
    args = parser.parse_args()
    print(json.dumps(prune(args.runtime, apply=args.apply), indent=2))
