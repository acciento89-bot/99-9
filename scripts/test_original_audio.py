#!/usr/bin/env python3
"""Offline sample-level checks against regenerated, actually shipped WAV files."""
import array
import hashlib
import json
import math
import pathlib
import subprocess
import sys
import tempfile
import unittest
import wave

ROOT = pathlib.Path(__file__).resolve().parents[1]


class OriginalAudioTests(unittest.TestCase):
    def test_reproduction_and_pcm_contract(self):
        with tempfile.TemporaryDirectory() as folder:
            result = subprocess.run([sys.executable, str(ROOT / "scripts/generate_original_audio.py"), "--output", folder], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            provenance = json.loads((ROOT / "assets/audio/PROVENANCE.json").read_text())
            self.assertEqual(provenance["generatorSha256"], hashlib.sha256((ROOT / "scripts/generate_original_audio.py").read_bytes()).hexdigest())
            self.assertEqual(set(provenance["outputs"]), {"precision-loop.wav", "ui.wav", "hit.wav", "miss.wav"})
            self.assertEqual({p.name for p in (ROOT / "assets/audio").glob("*.wav")}, set(provenance["outputs"]))
            for filename, receipt in provenance["outputs"].items():
                with self.subTest(filename=filename):
                    actual = (ROOT / "assets/audio" / filename).read_bytes()
                    self.assertEqual(actual, (pathlib.Path(folder) / filename).read_bytes())
                    self.assertEqual(hashlib.sha256(actual).hexdigest(), receipt["sha256"])
                    with wave.open(str(ROOT / "assets/audio" / filename)) as wav:
                        self.assertEqual((wav.getnchannels(), wav.getsampwidth(), wav.getframerate()), (1, 2, 22050))
                        samples = array.array("h", wav.readframes(wav.getnframes()))
                        if sys.byteorder != "little": samples.byteswap()
                        self.assertGreater(len(samples), 1000)
                        self.assertLessEqual(len(samples), 24 * 22050)
                        self.assertEqual(samples[0], 0)
                        self.assertEqual(samples[-1], 0)
                        self.assertLess(max(abs(v) for v in samples), 20000)
                        rms = math.sqrt(sum(v * v for v in samples) / len(samples)) / 32768
                        self.assertGreater(rms, .005)
                        self.assertLess(rms, .18)
                        # Endpoints alone do not detect an abrupt step beside the seam.
                        self.assertLess(max(abs(samples[i + 1] - samples[i]) for i in range(32)), 150)
                        self.assertLess(max(abs(samples[-i - 1] - samples[-i - 2]) for i in range(32)), 150)
                        if filename == "precision-loop.wav":
                            self.assertEqual(len(samples), 24 * 22050)
                            self.assertLess(rms, .09)

    def test_android_exports_original_audio_and_notice(self):
        import configparser
        import fnmatch
        cfg = configparser.ConfigParser(interpolation=None)
        cfg.read(ROOT / "export_presets.cfg")
        include = cfg["preset.1"]["include_filter"].strip('"').split(',')
        exclude = cfg["preset.1"]["exclude_filter"].strip('"').split(',')
        for filename in ["precision-loop.wav", "ui.wav", "hit.wav", "miss.wav", "NOTICE.txt", "PROVENANCE.json"]:
            path = "assets/audio/" + filename
            self.assertTrue(any(fnmatch.fnmatchcase(path, pattern) for pattern in include), path)
            self.assertFalse(any(fnmatch.fnmatchcase(path, pattern) for pattern in exclude), path)

    def test_actual_main_scene_uses_audio_subclass(self):
        project = (ROOT / "project.godot").read_text()
        self.assertIn('run/main_scene="res://scenes/main.tscn"', project)
        scene = (ROOT / "scenes/main.tscn").read_text()
        self.assertIn('[ext_resource type="Script" path="res://scripts/main_audio.gd" id="1_main"]', scene)
        self.assertIn('script = ExtResource("1_main")', scene)
        self.assertTrue((ROOT / "scripts/main_audio.gd").read_text().startswith('extends "res://scripts/main_practice.gd"'))


if __name__ == "__main__": unittest.main()
