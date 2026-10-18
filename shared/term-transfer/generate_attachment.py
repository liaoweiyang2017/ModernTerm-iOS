"""ASCII-password fixture for OS keyboard UI tests; synthetic reference entries only."""
from pathlib import Path
import hashlib, struct, json
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
root = Path(__file__).parent
entries = json.loads((root / 'reference.json').read_text())['entries']
plain = json.dumps(dict(schemaVersion=1, entries=entries), ensure_ascii=False, separators=(',', ':')).encode()
salt = bytes(range(16)); nonce = bytes(range(16, 28))
header = b'MTERM\0\r\n' + struct.pack('>HBBI', 1, 1, 1, 600000) + salt + nonce + struct.pack('>I', len(plain))
key = hashlib.pbkdf2_hmac('sha256', b'attachment-test-2026', salt, 600000, 32)
(root / 'attachment.term').write_bytes(header + AESGCM(key).encrypt(nonce, plain, header))
