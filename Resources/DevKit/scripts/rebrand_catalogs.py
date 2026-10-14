#!/usr/bin/env python3
"""Apply the product name and support links to tracked string catalogs."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
REPLACEMENTS = {
    "FlowDown.AI": "Jonwork",
    "FlowDown": "Jonwork",
    "https://flowdown.ai/docs/": "https://github.com/xiz2680/jonwork-ios",
    "https://flowdown.ai/": "https://github.com/xiz2680/jonwork-ios",
    "https://discord.gg/UHKMRyJcgc": "https://github.com/xiz2680/jonwork-ios/issues",
}


def rebrand(value):
    if isinstance(value, str):
        if "copyright" in value.lower():
            return value
        for old, new in REPLACEMENTS.items():
            value = value.replace(old, new)
        return value
    if isinstance(value, list):
        return [rebrand(item) for item in value]
    if isinstance(value, dict):
        return {rebrand(key): rebrand(item) for key, item in value.items()}
    return value


for directory in ("Jonwork", "JonworkTranslationProvider", "JonworkWidgets"):
    for path in (ROOT / directory).rglob("*.xcstrings"):
        original = path.read_text()
        updated = json.dumps(rebrand(json.loads(original)), ensure_ascii=False, indent=2) + "\n"
        if original != updated:
            path.write_text(updated)
            print(f"[+] rebranded {path.relative_to(ROOT)}")
