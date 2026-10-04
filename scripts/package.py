"""Builds dist/chat-delay-v<version>.zip, ready to extract into Chatterino's Plugins folder."""

import json
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PLUGIN = ROOT / "plugin"
FOLDER = "chat-delay"  # the plugin's ID in Chatterino

version = json.loads((PLUGIN / "info.json").read_text(encoding="utf-8"))["version"]
out = ROOT / "dist" / f"chat-delay-v{version}.zip"
out.parent.mkdir(exist_ok=True)

files = [PLUGIN / "info.json", *sorted(PLUGIN.glob("*.lua"))]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
    for f in files:
        zf.write(f, f"{FOLDER}/{f.name}")

print(out)
for f in files:
    print(f"  {FOLDER}/{f.name}")
