#!/usr/bin/env python3
import re
import sys
from pathlib import Path

root = Path('lib')
if not root.exists():
    print('lib folder not found')
    sys.exit(1)

pattern = re.compile(r"withValues\(alpha: \(([^)]+?)\s*\*\s*255\)\.round\(\)\)")
count = 0
files_changed = []
for path in root.rglob('*'):
    if 'dart' not in path.name:
        continue
    try:
        text = path.read_text(encoding='utf-8')
    except Exception as e:
        print(f"Skipping {path}: {e}")
        continue
    new_text, n = pattern.subn(r"withValues(alpha: \1)", text)
    if n > 0:
        path.write_text(new_text, encoding='utf-8')
        count += n
        files_changed.append(str(path))

print(f'Updated {count} occurrences in {len(files_changed)} files')
for f in files_changed:
    print(f)
