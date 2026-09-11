#!/usr/bin/env python3
"""Fail if launcher/Store identity drifts or the rasterized lettering disappears."""
import hashlib
import json
from pathlib import Path
from PIL import Image, ImageChops

root = Path(__file__).resolve().parents[1]
manifest = json.loads((root / "store/google-play/icon-manifest.json").read_text())
for name, sha in manifest.items():
    assert hashlib.sha256((root/name).read_bytes()).hexdigest() == sha, f"Regenerate all launcher/Store assets together: {name}"
for name, size in [("assets/icon.png",1024),("store/google-play/icon-512.png",512),("assets/android/icon-foreground.png",432),("assets/android/icon-background.png",432)]:
    with Image.open(root/name) as image:
        image.load()
        assert image.size == (size,size) and image.mode == "RGBA", name
        if "background" not in name:
            # The original icon includes a large white 99.9; an SVG importer
            # dropping text leaves no white pixels in this upper central area.
            pixels = image.crop((size//5,size//4,size*9//10,size*3//5)).getdata()
            threshold = .01 if "foreground" in name else .02
            assert sum(1 for r,g,b,a in pixels if r>225 and g>225 and b>225 and a>200) > size*size*threshold, f"Missing 99.9 lettering: {name}"
preset = (root / "export_presets.cfg").read_text()
for key,path in [("main_192x192","assets/icon.png"),("adaptive_foreground_432x432","assets/android/icon-foreground.png"),("adaptive_background_432x432","assets/android/icon-background.png")]:
    assert f'launcher_icons/{key}="res://{path}"' in preset
assert 'package/name="99.9%"' in preset
assert 'package/unique_name="de.kamilunavo.ninenine"' in preset
print("Launcher lettering, original artwork hashes, PNG integrity and Android identity verified")
