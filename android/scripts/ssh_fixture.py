#!/usr/bin/env python3
"""Isolated SSH/SFTP fixture. Never uses real accounts, keys or credentials."""
import base64,hashlib,json,os,pathlib,secrets,socket,subprocess,sys,tempfile,threading,time
import paramiko
import signal
def stop_fixture(*args): raise KeyboardInterrupt
signal.signal(signal.SIGTERM,stop_fixture)
root=pathlib.Path(__file__).resolve().parents[1]
assets=root/'app/src/androidTest/assets'
assets.mkdir(parents=True,exist_ok=True)
fixture=assets/'ssh-fixture.json'
if fixture.exists(): raise SystemExit('Refusing to overwrite test fixture')
folder=tempfile.TemporaryDirectory(prefix='modernterm-android-ssh-')
base=pathlib.Path(folder.name)
password=secrets.token_urlsafe(24); passphrase=secrets.token_urlsafe(16); username='test-account@ZONE-M6'
key=paramiko.RSAKey.generate(2048)
keys={}; public=[]
for kind in ['rsa','ed25519']:
 for encrypted in [False,True]:
  name=kind+('-encrypted' if encrypted else '')
  path=base/name
  subprocess.run(['ssh-keygen','-q','-t',kind,'-N',passphrase if encrypted else '', '-f',str(path)],check=True)
  keys[name]=path.read_text();public.append(path.with_suffix('.pub').read_text().split()[1])
remote=(base/'remote').resolve();remote.mkdir()
def local(path):
 p=(remote/path) if not path.startswith('/') else pathlib.Path(path)
 p=p.resolve()
 if p!=remote and remote not in p.parents: raise PermissionError('Outside fixture')
 return p
class Files(paramiko.SFTPServerInterface):
 def canonicalize(self,path):
  try: return str(local(path))
  except Exception: return str(remote)
 def list_folder(self,path):
  try:
   result=[]
   for p in local(path).iterdir():
    a=paramiko.SFTPAttributes.from_stat(p.stat());a.filename=p.name;result.append(a)
   return result
  except OSError as e:return paramiko.SFTPServer.convert_errno(e.errno or 13)
 def stat(self,path):
  try:return paramiko.SFTPAttributes.from_stat(local(path).stat())
  except OSError as e:return paramiko.SFTPServer.convert_errno(e.errno or 13)
 lstat=stat
 def open(self,path,flags,attr):
  try:
   fd=os.open(local(path),flags,0o600)
   f=os.fdopen(fd, 'r+b' if flags & os.O_RDWR else 'wb' if flags & os.O_WRONLY else 'rb')
   h=paramiko.SFTPHandle(flags);h.readfile=f;h.writefile=f;return h
  except OSError as e:return paramiko.SFTPServer.convert_errno(e.errno or 13)
 def remove(self,path):
  try:local(path).unlink();return paramiko.SFTP_OK
  except OSError as e:return paramiko.SFTPServer.convert_errno(e.errno or 13)
 def rmdir(self,path):
  try:local(path).rmdir();return paramiko.SFTP_OK
  except OSError as e:return paramiko.SFTPServer.convert_errno(e.errno or 13)
 def mkdir(self,path,attr):
  try:local(path).mkdir();return paramiko.SFTP_OK
  except OSError as e:return paramiko.SFTPServer.convert_errno(e.errno or 13)
 def rename(self,old,new):
  try:local(old).rename(local(new));return paramiko.SFTP_OK
  except OSError as e:return paramiko.SFTPServer.convert_errno(e.errno or 13)
class Server(paramiko.ServerInterface):
 def __init__(self,restricted=False):
  super().__init__();self.restricted=restricted
 def check_channel_subsystem_request(self,channel,name):
  return False if self.restricted else super().check_channel_subsystem_request(channel,name)
 def check_auth_password(self,user,value):return paramiko.AUTH_SUCCESSFUL if user==username and secrets.compare_digest(value,password) else paramiko.AUTH_FAILED
 def check_auth_publickey(self,user,key):return paramiko.AUTH_SUCCESSFUL if user==username and key.get_base64() in public else paramiko.AUTH_FAILED
 def get_allowed_auths(self,user):return 'password,publickey'
 def check_channel_request(self,kind,channel):return paramiko.OPEN_SUCCEEDED if kind=='session' else paramiko.OPEN_FAILED_ADMINISTRATIVELY_PROHIBITED
 def check_channel_pty_request(self,*args):return True
 def check_channel_window_change_request(self,*args):return True
 def check_channel_shell_request(self,channel):
  def echo():
   try:
    channel.send(b'READY\r\n')
    while True:
     data=channel.recv(8192)
     if not data:break
     channel.send(data)
   except Exception:pass
  threading.Thread(target=echo,daemon=True).start();return True
 def check_channel_exec_request(self,channel,command):
  if self.restricted:return False
  def execute():
   try:
    result=subprocess.run(command.decode(),shell=True,cwd=remote,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=12)
    channel.sendall(result.stdout);channel.send_exit_status(result.returncode)
   except Exception:channel.send_exit_status(1)
   finally:channel.close()
  threading.Thread(target=execute,daemon=True).start();return True
transports=[]
def serve(client,mode="normal"):
 t=paramiko.Transport(client);transports.append(t)
 t.get_security_options().key_types=('ssh-rsa',) if mode=='legacy' else ('rsa-sha2-512','rsa-sha2-256')
 t.add_server_key(key);t.set_subsystem_handler('sftp',paramiko.SFTPServer,Files)
 try:t.start_server(server=Server(mode=="restricted"))
 except Exception:t.close()
def extra(port,mode):
 sock=socket.socket();sock.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1);sock.bind(('127.0.0.1',port));sock.listen()
 while True:
  client,_=sock.accept();threading.Thread(target=serve,args=(client,mode),daemon=True).start()
threading.Thread(target=extra,args=(22223,'restricted'),daemon=True).start()
threading.Thread(target=extra,args=(22224,'legacy'),daemon=True).start()
listener=socket.socket();listener.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1);listener.bind(('127.0.0.1',22222));listener.listen()
with fixture.open('x') as f:
 os.chmod(fixture,0o600)
 json.dump(dict(host=os.environ.get('FIXTURE_HOST','10.0.2.2'),platform=sys.platform,port=22222,user=username,password=password,passphrase=passphrase,keys=keys,directory=str(remote),fingerprint='SHA256:'+base64.b64encode(hashlib.sha256(key.asbytes()).digest()).decode().rstrip('=')),f)
try:
 print('Fixture ready on port 22222',flush=True)
 while True:
  client,_=listener.accept();threading.Thread(target=serve,args=(client,),daemon=True).start()
finally:
 for t in transports:t.close()
 listener.close();fixture.unlink(missing_ok=True);folder.cleanup()
