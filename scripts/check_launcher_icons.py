#!/usr/bin/env python3
"""Fail if launcher/Store identity drifts or the rasterized lettering disappears."""
import hashlib
import json
from pathlib import Path
from PIL import Image

root = Path(__file__).resolve().parents[1]
manifest = json.loads((root / "store/google-play/icon-manifest.json").read_text())
for name, sha in manifest.items():
    assert hashlib.sha256((root/name).read_bytes()).hexdigest() == sha, f"Regenerate all launcher/Store assets together: {name}"
for name, size in [("assets/icon.png",1024),("store/google-play/icon-512.png",512)]:
    with Image.open(root/name) as image:
        image.load()
        assert image.size == (size,size) and image.mode == "RGBA", name
        # The original icon includes a large white 99.9; an SVG importer
        # dropping text leaves no white pixels in this upper central area.
        pixels = image.crop((size//5,size//4,size*9//10,size*3//5)).getdata()
        assert sum(1 for r,g,b,a in pixels if r>225 and g>225 and b>225 and a>200) > size*size*.02, f"Missing 99.9 lettering: {name}"
preset = (root / "export_presets.cfg").read_text()
assert 'launcher_icons/main_192x192="res://assets/icon.png"' in preset
assert 'launcher_icons/adaptive_' not in preset
assert not (root / "assets/android").exists()
assert 'config/icon="res://assets/icon.svg"' in (root / "project.godot").read_text()
assert 'package/name="99.9%"' in preset
assert 'package/unique_name="de.kamilunavo.ninenine"' in preset
print("iOS and Android share the canonical SVG; direct Android launcher, lettering, hashes and PNG integrity verified")
