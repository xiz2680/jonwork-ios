#!/usr/bin/env python3
"""Check compiler-extracted keys in changed app sources against every locale."""
import argparse
import json
import hashlib
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--derived-data", required=True, type=Path)
parser.add_argument("--catalog", required=True, type=Path)
parser.add_argument("--manifest", type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[3]
if args.manifest:
    rows = json.loads(args.manifest.read_text())["files"]
    names = [row["path"] for row in rows if row["path"].startswith("Jonwork/") and row["path"].endswith(".swift")]
    for row in rows:
        if row["path"] in names and hashlib.sha256((root / row["path"]).read_bytes()).hexdigest() != row["sha256"]:
            raise SystemExit("[-] source differs from manifest: " + row["path"])
    print("[+] extraction input manifest: " + str(args.manifest))
else:
    names = subprocess.check_output(
        ["git", "ls-files", "--modified", "--others", "--exclude-standard", "-z"], cwd=root,
    ).decode().split("\0")
sources = {str((root / name).resolve()) for name in names if name.startswith("Jonwork/") and name.endswith(".swift")}
if not sources:
    raise SystemExit("[-] no source inputs; provide the reviewed source manifest on a clean HEAD")
for source in sorted(sources):
    print("[+] extraction source: " + str(Path(source).relative_to(root)))
catalog = json.loads(args.catalog.read_text())["strings"]
keys = set()
extracted = set()
for path in args.derived_data.glob("Build/Intermediates.noindex/Jonwork.build/Debug-iphonesimulator/Jonwork.build/Objects-normal/*/*.stringsdata"):
    data = json.loads(path.read_text())
    source = data.get("source")
    if not isinstance(source, str) or not source:
        continue
    source = str(Path(source).resolve())
    if source not in sources:
        continue
    extracted.add(source)
    keys.update(row["key"] for row in data.get("tables", {}).get("Localizable", []))
missing = []
for key in sorted(keys):
    for locale in ["en", "de", "es", "fr", "ja", "ko", "zh-Hans"]:
        unit = catalog.get(key, {}).get("localizations", {}).get(locale, {}).get("stringUnit", {})
        if not unit.get("value") or unit.get("state") != "translated":
            missing.append((key, locale))
if sources - extracted:
    for source in sorted(sources - extracted):
        print("[-] missing extraction: " + str(Path(source).relative_to(root)))
if missing:
    for key, locale in missing:
        print("[-] missing translation: " + locale + " / " + key)
if not keys:
    print("[-] no compiler-extracted keys")
if missing or sources - extracted or not keys:
    raise SystemExit(1)
print(f"[+] checked {len(keys)} extracted keys in {len(extracted)} changed app sources across seven locales")
