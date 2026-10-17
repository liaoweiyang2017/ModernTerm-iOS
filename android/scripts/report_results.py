#!/usr/bin/env python3
"""Print test outcomes to the run log/summary, independent of artifact quota."""
import os,pathlib,xml.etree.ElementTree as ET
root=pathlib.Path(__file__).resolve().parents[1]/'app/build'
lines=['## Android test outcomes']
for location in ['test-results','outputs/androidTest-results']:
 for p in (root/location).rglob('TEST*.xml'):
  t=ET.parse(p).getroot();lines.append(f"- {t.get('name')}: {t.get('tests')} tests, {t.get('failures')} failures, {t.get('errors')} errors")
  for case in t.iter('testcase'):
   failure=case.find('failure')
   if failure is not None:lines.append(f"  - {case.get('name')}: {(failure.text or '')[:1400]}")
for p in (root/'outputs/androidTest-results').rglob('logcat-*TermTransferTest-referenceUnicodeAndRandomRoundTrip.txt'):
 for line in p.read_text(errors='replace').splitlines():
  if 'TERM_KDF_AND_DECODE_MS=' in line:
   value=line.split('TERM_KDF_AND_DECODE_MS=',1)[1].strip()
   if value.isdigit():lines.append(f"- File KDF + decode: {value} ms")
text='\n'.join(lines);print(text)
if os.environ.get('GITHUB_STEP_SUMMARY'):
 with open(os.environ['GITHUB_STEP_SUMMARY'],'a') as f:f.write(text+'\n')
