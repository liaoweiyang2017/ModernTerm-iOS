#!/usr/bin/env python3
"""Opt-in handshake probe; rejects the host key and never submits credentials."""
import json, os, pathlib, subprocess, sys
root = pathlib.Path(__file__).resolve().parents[1]
if len(sys.argv) != 2:
    raise SystemExit('Usage: python3 Scripts/gateway_probe.py HOST')
fixture = root/'Tests/GatewayProbe.json'
if fixture.exists(): raise SystemExit('Refusing to overwrite probe configuration')
try:
    fixture.write_text(json.dumps(dict(host=sys.argv[1])))
    subprocess.run(['xcodegen', 'generate'], cwd=root, check=True)
    subprocess.run(['xcodebuild', '-project', 'ModerntermIOS.xcodeproj', '-scheme', 'ModerntermIOS',
      '-destination', 'platform=iOS Simulator,id='+os.environ.get('MODERNTERM_SIMULATOR','CFC84B07-C214-4DA5-84BD-773EBF76FFCC'),
      '-derivedDataPath', os.environ.get('MODERNTERM_DERIVED_DATA','build'),
      '-only-testing:ModerntermTests/GatewayProbeTests',
      'CODE_SIGNING_ALLOWED=YES', 'CODE_SIGN_IDENTITY=-', 'test'], cwd=root, check=True)
finally:
    fixture.unlink(missing_ok=True)
    subprocess.run(['xcodegen', 'generate'], cwd=root, check=True)
