#!/usr/bin/env python3
"""Rasterize the original icon.svg, preserving its text in Android exports."""
from pathlib import Path
import copy
import hashlib
import json
import subprocess
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/icon.svg"
SVG = "{http://www.w3.org/2000/svg}"
ET.register_namespace("", SVG[1:-1])

def render(tree, path, size):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as temp:
        source = Path(temp) / "icon.svg"
        ET.ElementTree(tree).write(source, encoding="utf-8", xml_declaration=True)
        subprocess.run(["inkscape", str(source), f"--export-filename={path}", f"--export-width={size}", f"--export-height={size}"], check=True)

original = ET.parse(SOURCE).getroot()
render(original, ROOT / "assets/icon.png", 1024)
render(original, ROOT / "store/google-play/icon-512.png", 512)

# Android masks the adaptive layers. Preserve the original artwork and colors;
# apply only safe-area padding to keep the percentage and bar inside the mask.
foreground = copy.deepcopy(original)
children = list(foreground)
for child in children:
    foreground.remove(child)
foreground.append(children[0])  # gradient definition
group = ET.SubElement(foreground, SVG+"g", transform="translate(184.32 184.32) scale(0.64)")
for child in children[2:]:  # background is exported separately
    group.append(child)
render(foreground, ROOT / "assets/android/icon-foreground.png", 432)
background = copy.deepcopy(original)
for child in list(background)[2:]:
    background.remove(child)
render(background, ROOT / "assets/android/icon-background.png", 432)

paths = ["assets/icon.svg", "assets/icon.png", "assets/android/icon-foreground.png", "assets/android/icon-background.png", "store/google-play/icon-512.png"]
(ROOT / "store/google-play/icon-manifest.json").write_text(json.dumps({p: hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths}, indent=2)+"\n")
