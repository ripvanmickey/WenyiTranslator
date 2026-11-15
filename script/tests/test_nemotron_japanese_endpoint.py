import importlib
import sys
import unittest
from collections import deque
from pathlib import Path
from types import ModuleType, SimpleNamespace
from unittest.mock import patch


PROJECT = Path(__file__).resolve().parents[2] / "Resources" / "ASRProject"


def load_asr():
    # Exercise the actual endpoint state machine without loading models or using Metal.
    stubs = {
        name: ModuleType(name)
        for name in ("mlx", "mlx.core", "numpy", "livecaption.audio", "livecaption.runtime")
    }
    stubs["mlx"].core = stubs["mlx.core"]
    stubs["livecaption.audio"].SENTINEL = object()
    stubs["livecaption.runtime"].MLX_LOCK = object()
    with patch.dict(sys.modules, stubs), patch.object(sys, "path", [str(PROJECT), *sys.path]):
        return importlib.import_module("livecaption.asr")


asr = load_asr()


class JapaneseEndpointTests(unittest.TestCase):
    def stream(self, text, *, japanese=True, seconds=3, tokens=()):
        stream = asr.OnlineStream.__new__(asr.OnlineStream)
        stream._active = True
        stream._audio = deque()
        stream._n_samples = int(seconds * asr.config.SAMPLE_RATE)
        stream._silence_frames = 0
        stream._diar = None
        stream._japanese_endpointing = japanese
        stream._text = text
        stream._hypothesis = [SimpleNamespace(text=token) for token in tokens]
        stream._drive = lambda **kwargs: [("partial", stream._text)]
        stream._finalize = lambda split_token=None: [("final", split_token)]
        return stream

    def silence(self, stream, frames):
        return [
            event
            for _ in range(frames)
            for event in stream._on_frame(range(asr._VAD_FRAME), False)
        ]

    def test_japanese_sentence_marks_confirm_on_short_pause(self):
        for mark in ("。", "！？", "！", "？」"):
            with self.subTest(mark=mark):
                stream = self.stream("いかがですか" + mark)
                self.assertNotIn(("final", None), self.silence(stream, 18))
                self.assertIn(("final", None), self.silence(stream, 1))

    def test_unfinished_ending_defers_final_but_keeps_partials(self):
        stream = self.stream("そう思ったけど、")
        events = self.silence(stream, 38)
        self.assertIn(("partial", "そう思ったけど、"), events)
        self.assertNotIn(("final", None), events)
        self.assertIn(("final", None), self.silence(stream, 10))

    def test_punctuation_overrides_the_continuation_heuristic(self):
        stream = self.stream("そう思ったけど。")
        self.assertIn(("final", None), self.silence(stream, 19))

    def test_soft_limit_retains_japanese_closing_quote(self):
        stream = self.stream("前の話。次", seconds=8, tokens=["前の話", "。", "」", "次"])
        self.assertIn(("final", 2), stream._on_frame(range(asr._VAD_FRAME), True))

    def test_hard_limit_still_applies_to_unfinished_endings(self):
        stream = self.stream("まだ話しているけど", seconds=20)
        self.assertIn(("final", None), stream._on_frame(range(asr._VAD_FRAME), True))

    def test_non_japanese_uses_existing_rules(self):
        stream = self.stream("First.", japanese=False)
        self.assertIn(("final", None), self.silence(stream, 19))
        stream = self.stream("First。", japanese=False)
        self.assertNotIn(("final", None), self.silence(stream, 19))
        self.assertIn(("final", None), self.silence(stream, 19))


if __name__ == "__main__":
    unittest.main()
