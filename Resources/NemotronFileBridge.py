# coding: utf-8
"""Offline, bounded PCM-file recognition for Wenyi video preloading.

One model is loaded per job. Each request is acknowledged before the caller sends
another, so translation/checkpointing applies backpressure without dropping audio.
"""
import argparse
import contextlib
import json
import os
from pathlib import Path
import sys

OUTPUT = sys.stdout

def emit(value):
    OUTPUT.write(json.dumps(value, ensure_ascii=False) + '\n')
    OUTPUT.flush()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--runtime', required=True)
    parser.add_argument('--language', required=True)
    parser.add_argument('--scratch-root', required=True)
    args = parser.parse_args()
    root = Path(args.runtime).resolve()
    scratch = Path(args.scratch_root).resolve(strict=True)
    # Never download models or inherit authentication in this local-only worker.
    os.environ['HF_HUB_OFFLINE'] = '1'
    os.environ['TRANSFORMERS_OFFLINE'] = '1'
    from ASRModels import state
    if not state(root, 'nemotron'):
        raise RuntimeError('Nemotron model files are incomplete')
    with contextlib.redirect_stdout(sys.stderr):
        import numpy as np
        import mlx.core as mx
        from mlx_audio.stt import load
        from livecaption.languages import normalize_asr_language
        model = load(str(root / 'models/nemotron/files'))
        known = getattr(model, 'prompt_dictionary', None) or {}
        language = normalize_asr_language(args.language, known if known else None)
        if known and language not in known:
            raise RuntimeError('This language is not supported by the Nemotron model')
    emit({'type': 'ready'})
    for line in sys.stdin:
        if len(line) > 16384:
            raise RuntimeError('Request is too large')
        request = json.loads(line)
        path = Path(request['file']).resolve(strict=True)
        if not path.is_relative_to(scratch) or path.suffix != '.f32':
            raise RuntimeError('Audio file must be inside the job directory')
        size = path.stat().st_size
        if not 0 < size <= 16000 * 16 * 4 or size % 4:
            raise RuntimeError('Invalid PCM size')
        samples = np.fromfile(path, dtype='<f4')
        if not np.isfinite(samples).all():
            raise RuntimeError('Invalid PCM samples')
        with contextlib.redirect_stdout(sys.stderr):
            result = model.generate(mx.array(samples), language=language, verbose=False)
        emit({'type': 'text', 'id': request['id'], 'text': result.text.strip()})

if __name__ == '__main__':
    try:
        main()
    except BrokenPipeError:
        pass
    except Exception as error:
        emit({'type': 'error', 'message': str(error)[:500]})
        sys.exit(1)
