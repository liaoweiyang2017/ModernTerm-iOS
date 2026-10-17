# ModernTerm .term v1

Authenticated binary envelope shared by iOS and Android. These test fixtures contain **synthetic data only**; `TEST KEY` is not an SSH key. The fixture password is intentionally public in `reference.json`.

All integers are unsigned big endian. Header (48 bytes): magic `4d5445524d000d0a` (8), version 1 (u16), KDF 1 (u8), AEAD 1 (u8), iterations 600000 (u32), salt (16), nonce (12), ciphertext length excluding tag (u32). Follow with ciphertext and GCM tag (16). Authenticate the entire header as AAD. Reject other algorithms, versions, iteration counts, trailing bytes and lengths before KDF.

Key: PBKDF2-HMAC-SHA256, password NFC then UTF-8, 600000 iterations, 32 bytes. AEAD: AES-256-GCM, random fresh salt and nonce on every export. Password: at least 12 Unicode scalar values and at most 1024 UTF-8 bytes after NFC; whitespace significant. File and batch total limit: 16 MiB; 20 files; 200 input entries and 200 stored connections; private key ≤1 MiB.

Encrypted payload: UTF-8 JSON `{ "schemaVersion": 1, "entries": [{ "server": {...}, "credentials": {...} }] }`. Configuration fields: UUID, name, host, port, user, group, favorite, keyLogin, optional distribution (default Ubuntu). Credentials absent means configuration only; when present, password/privateKey/passphrase are strings, including empty strings. No host trust, histories, macros or preferences. UUID comparisons ignore case. Passwords/private key text are never normalized.

`reference.term` is deterministic Python AESGCM/PBKDF2 vector; generator uses fixed randomness **only for this reference**. `android-export.term` and `ios-export.term` are actual randomized outputs from the platform test codecs. Both test suites decode the other platform's file and compare complete records, including Unicode and absent credentials. They are test resources only, never packaged in production apps.

API references: [Android SecretKeyFactory](https://developer.android.com/reference/javax/crypto/SecretKeyFactory) documents PBKDF2WithHmacSHA256 support since API26; [Apple CommonCrypto implementation](https://github.com/apple-oss-distributions/CommonCrypto/blob/main/lib/CommonKeyDerivation.c) exposes PBKDF2 with explicit password byte length. Tests independently verify NFC/decomposed passwords and emoji across providers.
