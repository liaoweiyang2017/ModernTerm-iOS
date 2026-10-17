#!/usr/bin/env python3
"""Build with the fixed local signing identity without exposing passwords in argv."""
import json,os,pathlib,subprocess
root=pathlib.Path(__file__).resolve().parents[1]
meta=pathlib.Path.home()/'.codex/private/modernterm-android/credentials.json'
if not meta.exists():raise SystemExit('Configure a dedicated release keystore first; see android/README.md.')
value=json.loads(meta.read_text());env=os.environ.copy()
env.update(MT_STORE_FILE=value['keystore'],MT_STORE_PASSWORD=value['password'],MT_KEY_ALIAS=value['alias'])
subprocess.run([str(root/'gradlew'),'-p',str(root),'--project-cache-dir',str(pathlib.Path.home()/'.cache/modernterm-android-gradle'),':app:assembleRelease'],env=env,check=True)
