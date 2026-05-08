#!/usr/bin/env python3
import re
import sys
from pathlib import Path

root = Path('lib')
if not root.exists():
    print('lib folder not found')
    sys.exit(1)

pattern = re.compile(r"\.withOpacity\(\s*([^\)]+?)\s*\)")
count = 0
files_changed = []
for path in root.rglob('*'):
    # only process files that contain 'dart' in name or end with .dart-like patterns
    if 'dart' not in path.name:
        continue
    try:
        text = path.read_text(encoding='utf-8')
    except Exception as e:
        print(f"Skipping {path}: {e}")
        continue
    new_text, n = pattern.subn(r".withValues(alpha: (\\1 * 255).round())", text)
    if n > 0:
        try:
            path.write_text(new_text, encoding='utf-8')
            count += n
            files_changed.append(str(path))
        except Exception as e:
            print(f"Failed to write {path}: {e}")

print(f'Updated {count} occurrences in {len(files_changed)} files')
for f in files_changed:
    print(f)
