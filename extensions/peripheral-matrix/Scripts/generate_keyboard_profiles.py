"""Convert pinned VIA definitions into audited, offline keyboard profiles.

Usage: python3 generate_keyboard_profiles.py DEFINITIONS_DIRECTORY OUTPUT_JSON
The input directory contains sources.json (filename stem -> pinned source URL)
and corresponding JSON files. No network access or firmware writes occur.
"""
import hashlib
import json
import re
import sys
from pathlib import Path


def convert(name, source, raw):
    definition = json.loads(raw)
    rows, columns = definition['matrix']['rows'], definition['matrix']['cols']
    keys, y = [], 0
    for line in definition['layouts']['keymap']:
        x, width, height = 0, 1, 1
        for item in line:
            if isinstance(item, dict):
                if any(item.get(k, 0) for k in ('r', 'rx', 'ry')):
                    raise ValueError('Rotated layouts require separate geometry support')
                x += item.get('x', 0)
                y += item.get('y', 0)
                width, height = item.get('w', width), item.get('h', height)
            else:
                match = re.fullmatch(r'\s*(\d+)\s*,\s*(\d+)\s*', item.split('\n')[0])
                if not match:
                    raise ValueError('Unsupported matrix label')
                row, column = map(int, match.groups())
                assert 0 <= row < rows and 0 <= column < columns
                assert x >= 0 and y >= 0 and width > 0 and height > 0
                keys.append(dict(row=row, column=column, x=x, y=y, width=width, height=height))
                x += width
                width, height = 1, 1
        y += 1
    assert len({(k['row'], k['column']) for k in keys}) == len(keys)
    return dict(id='keychron/' + name, name=definition['name'], vendor=int(definition['vendorId'], 16),
                product=int(definition['productId'], 16), rows=rows, columns=columns, layers=4,
                keys=keys, customNames=[k['name'] for k in definition.get('customKeycodes', [])],
                source=source, sha256=hashlib.sha256(raw).hexdigest())


if __name__ == '__main__':
    directory, output = map(Path, sys.argv[1:])
    sources = json.loads((directory / 'sources.json').read_text())
    profiles = [convert(name, url, (directory / (name + '.json')).read_bytes()) for name, url in sources.items()]
    assert len({(p['vendor'], p['product']) for p in profiles}) == len(profiles)
    output.write_text(json.dumps(profiles, separators=(',', ':')) + '\n')
    print(f'Generated {len(profiles)} pinned profiles')
