#!/usr/bin/env python3
"""Disposable localhost OpenSSH fixture. Never reads existing SSH keys or sessions."""
import getpass,json,os,pathlib,socket,subprocess,tempfile,time
root=pathlib.Path(__file__).resolve().parents[1]
simulator=os.environ.get('MODERNTERM_SIMULATOR','CFC84B07-C214-4DA5-84BD-773EBF76FFCC')
fixture=root/'Tests/Fixture.json'
if fixture.exists():raise SystemExit('Refusing to replace existing test fixture')
with tempfile.TemporaryDirectory(prefix='modernterm-ios-ssh-') as folder:
 p=pathlib.Path(folder);remote=p/'remote';remote.mkdir()
 for name in ['host','client']:
  subprocess.run(['/usr/bin/ssh-keygen','-q','-t','ed25519','-N','','-f',str(p/name)],check=True)
 (p/'authorized_keys').write_bytes((p/'client.pub').read_bytes())
 with socket.socket() as sock:sock.bind(('127.0.0.1',0));port=sock.getsockname()[1]
 (p/'sshd_config').write_text(f'''Port {port}
ListenAddress 127.0.0.1
HostKey {p}/host
PidFile {p}/pid
AuthorizedKeysFile {p}/authorized_keys
StrictModes no
PasswordAuthentication no
KbdInteractiveAuthentication no
UsePAM no
Subsystem sftp /usr/libexec/sftp-server
''')
 with (p/'sshd.log').open('w') as log:
  server=subprocess.Popen(['/usr/sbin/sshd','-D','-e','-f',str(p/'sshd_config')],stderr=log)
  try:
   time.sleep(.5)
   if server.poll() is not None:raise RuntimeError('Temporary sshd failed to start')
   hostkey=' '.join((p/'host.pub').read_text().split()[:2])
   fixture.write_text(json.dumps(dict(port=port,user=getpass.getuser(),key=(p/'client').read_text(),hostKey=hostkey,directory=str(remote))));fixture.chmod(0o600)
   subprocess.run(['/opt/homebrew/bin/xcodegen','generate'],cwd=root,check=True)
   subprocess.run(['xcodebuild','-project','ModerntermIOS.xcodeproj','-scheme','ModerntermIOS','-destination',f'platform=iOS Simulator,id={simulator}','-derivedDataPath','build','CODE_SIGNING_ALLOWED=YES','CODE_SIGN_IDENTITY=-','test'],cwd=root,check=True)
  finally:
   server.terminate();server.wait(timeout=5)
   fixture.unlink(missing_ok=True)
   subprocess.run(['/opt/homebrew/bin/xcodegen','generate'],cwd=root,check=True)
