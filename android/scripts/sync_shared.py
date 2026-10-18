#!/usr/bin/env python3
"""Generate Android copies from iOS-owned public resources; --check detects drift."""
import pathlib,re,sys,textwrap
root=pathlib.Path(__file__).resolve().parents[2]
script=re.search(r'static let script = #"""\n(.*?)\n    """#', (root/'ios/Sources/ServerMetrics.swift').read_text(), re.S).group(1)
outputs={root/'android/app/src/main/assets/monitor.sh':textwrap.dedent(script).encode(),root/'android/app/src/main/assets/palettes.json':(root/'ios/Resources/palettes.json').read_bytes()}
for path,data in outputs.items():
 if '--check' in sys.argv:
  assert path.exists() and path.read_bytes()==data, f'Shared resource drift: {path.name}'
 else:path.write_bytes(data)
