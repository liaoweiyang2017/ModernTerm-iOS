"""Synthetic interoperability fixture only; no real credentials. Requires cryptography."""
import hashlib, json, struct
from pathlib import Path
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
root = Path(__file__).parent
password = '互通测试-café-🔐-2026'
entries = [dict(server=dict(id='11111111-2222-4333-8444-555555555555', name='测试 connection', host='ssh.example.invalid', port=2222, user='test@ZC-M6', group='跨平台', favorite=True, keyLogin=True, distribution='Debian'), credentials=dict(password='synthetic-only', privateKey='TEST KEY\nnot-a-real-key\n', passphrase='口令')), dict(server=dict(id='aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee', name='Configuration only', host='2001:db8::1', port=22, user='User@Group', group='Servers', favorite=False, keyLogin=False, distribution='Ubuntu'))]
plain = json.dumps(dict(schemaVersion=1,entries=entries), ensure_ascii=False, separators=(',',':')).encode()
salt = bytes(range(16)); nonce = bytes(range(16,28))
header = b'MTERM\0\r\n'+struct.pack('>HBBI',1,1,1,600000)+salt+nonce+struct.pack('>I',len(plain))
key = hashlib.pbkdf2_hmac('sha256',password.encode(),salt,600000,32)
(root/'reference.term').write_bytes(header+AESGCM(key).encrypt(nonce,plain,header))
(root/'reference.json').write_text(json.dumps(dict(password=password, entries=entries),ensure_ascii=False,indent=2)+'\n')
