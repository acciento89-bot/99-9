#!/usr/bin/env python3
"""Rasterize the original icon.svg for iOS, Android and Google Play."""
from pathlib import Path
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

paths = ["assets/icon.svg", "assets/icon.png", "store/google-play/icon-512.png"]
(ROOT / "store/google-play/icon-manifest.json").write_text(json.dumps({p: hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths}, indent=2)+"\n")
