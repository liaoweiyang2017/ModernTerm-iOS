#!/usr/bin/env python3
"""Disposable RSA-SHA2/password SSH fixture; requires paramiko==4.0.0.
Runs the existing OpenSSH regression alongside this fixture. No user credentials.
"""
import json, os, pathlib, secrets, socket, subprocess, threading, tempfile
import paramiko
root = pathlib.Path(__file__).resolve().parents[1]
fixture = root / 'Tests/PasswordFixture.json'
if fixture.exists():
    raise SystemExit('Refusing to replace existing fixture')
password = secrets.token_urlsafe(24)
username = 'test-account@ZONE-M6'
key = paramiko.RSAKey.generate(2048)
key_directory = tempfile.TemporaryDirectory(prefix='modernterm-rsa-test-')
client_key_path = pathlib.Path(key_directory.name)/'client'
subprocess.run(['/usr/bin/ssh-keygen','-q','-t','rsa','-b','2048','-N','','-f',str(client_key_path)],check=True)
client_public = client_key_path.with_suffix('.pub').read_text().split()[1]
listener = socket.socket()
listener.bind(('127.0.0.1', 0))
listener.listen()
listener.settimeout(.5)
ipv6 = socket.socket(socket.AF_INET6)
ipv6.bind(('::1', 0))
ipv6.listen()
ipv6.settimeout(.5)
stop = threading.Event()
connections = []
class Server(paramiko.ServerInterface):
    def check_auth_password(self, user, supplied):
        return paramiko.AUTH_SUCCESSFUL if user == username and secrets.compare_digest(supplied, password) else paramiko.AUTH_FAILED
    def check_auth_publickey(self, user, key):
        return paramiko.AUTH_SUCCESSFUL if user == username and key.get_base64() == client_public else paramiko.AUTH_FAILED
    def get_allowed_auths(self, user): return 'password,publickey'
    def check_channel_request(self, kind, channel):
        return paramiko.OPEN_SUCCEEDED if kind == 'session' else paramiko.OPEN_FAILED_ADMINISTRATIVELY_PROHIBITED
    def check_channel_pty_request(self, *args): return True
    def check_channel_shell_request(self, channel):
        def echo():
            try:
                channel.send(b'FIXTURE_READY\r\n')
                while not stop.is_set():
                    data = channel.recv(4096)
                    if not data: break
                    channel.send(data)
            except (OSError, EOFError): pass
        threading.Thread(target=echo, daemon=True).start()
        return True
    def check_channel_exec_request(self, channel, command):
        channel.close()
        return False
    def check_channel_subsystem_request(self, channel, name):
        return False
    # Explicit channel closure mirrors servers which reject unsupported capabilities.
def serve(client):
    transport = paramiko.Transport(client)
    connections.append(transport)
    options = transport.get_security_options()
    options.key_types = ('rsa-sha2-512', 'rsa-sha2-256')
    transport.add_server_key(key)
    try: transport.start_server(server=Server())
    except (EOFError, OSError, paramiko.SSHException): transport.close()
def accept(listener):
    while not stop.is_set():
        try: client, _ = listener.accept()
        except socket.timeout: continue
        except OSError: break
        threading.Thread(target=serve, args=(client,), daemon=True).start()
threading.Thread(target=accept, args=(listener,), daemon=True).start()
threading.Thread(target=accept, args=(ipv6,), daemon=True).start()
try:
    descriptor = os.open(fixture, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, 'w') as output:
        json.dump(dict(port=listener.getsockname()[1], ipv6Port=ipv6.getsockname()[1], user=username, password=password,
                       hostKey=key.get_name()+' '+key.get_base64(), rsaKey=client_key_path.read_text()), output)
    subprocess.run(['python3', str(root/'Scripts/integration.py')], cwd=root, check=True)
finally:
    stop.set()
    listener.close()
    ipv6.close()
    for transport in connections: transport.close()
    fixture.unlink(missing_ok=True)
    key_directory.cleanup()
    subprocess.run(['xcodegen', 'generate'], cwd=root, check=True)
