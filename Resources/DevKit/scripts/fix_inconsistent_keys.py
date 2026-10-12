#!/usr/bin/env python3
"""
Fix localization entries where the key doesn't match the English translation.
Updates the key to match the English value.
"""

import json
import sys
from pathlib import Path


def fix_inconsistent_keys(xcstrings_path, dry_run=False):
    """Fix entries where key != English value by updating the key."""
    with open(xcstrings_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    
    strings = data.get('strings', {})
    fixed = []
    new_strings = {}
    
    for key, entry in strings.items():
        # Skip special entries
        if 'shouldTranslate' in entry and not entry['shouldTranslate']:
            new_strings[key] = entry
            continue
        
        localizations = entry.get('localizations', {})
        en_value = None
        
        # Get English value
        if 'en' in localizations:
            en_unit = localizations['en'].get('stringUnit', {})
            en_value = en_unit.get('value')
        
        # If there's no explicit English localization, keep original key
        if en_value is None:
            new_strings[key] = entry
            continue
        
        # Check if key matches English value
        if key != en_value:
            # Use English value as the new key
            new_strings[en_value] = entry
            fixed.append({
                'old_key': key,
                'new_key': en_value
            })
        else:
            new_strings[key] = entry
    
    if not fixed:
        print("✅ All keys already match their English translations!")
        return []
    
    if not dry_run:
        # Update the data
        data['strings'] = new_strings
        
        # Write back to file
        with open(xcstrings_path, 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        
        print(f"✅ Fixed {len(fixed)} entries in {xcstrings_path}")
    else:
        print(f"🔍 DRY RUN: Would fix {len(fixed)} entries")
    
    return fixed


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 fix_inconsistent_keys.py <path_to_Localizable.xcstrings> [--dry-run]")
        sys.exit(1)
    
    xcstrings_path = Path(sys.argv[1])
    dry_run = '--dry-run' in sys.argv
    
    if not xcstrings_path.exists():
        print(f"Error: File not found: {xcstrings_path}")
        sys.exit(1)
    
    print(f"{'[DRY RUN] ' if dry_run else ''}Fixing: {xcstrings_path}\n")
    
    fixed = fix_inconsistent_keys(xcstrings_path, dry_run)
    
    if fixed:
        print(f"\nFixed {len(fixed)} entries:")
        print("=" * 100)
        
        for i, item in enumerate(fixed, 1):
            print(f"\n{i}.")
            print(f"   Old key: {item['old_key'][:70]}{'...' if len(item['old_key']) > 70 else ''}")
            print(f"   New key: {item['new_key'][:70]}{'...' if len(item['new_key']) > 70 else ''}")
            print("-" * 100)
        
        if not dry_run:
            # Save mapping for reference
            mapping_file = xcstrings_path.parent / "key_mapping.json"
            with open(mapping_file, 'w', encoding='utf-8') as f:
                json.dump(fixed, f, ensure_ascii=False, indent=2)
            print(f"\n\nKey mapping saved to: {mapping_file}")


if __name__ == '__main__':
    main()

