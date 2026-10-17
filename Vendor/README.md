# Pinned SSH dependencies

These source snapshots make the compatibility fixes reproducible without changing a global package cache or relying on an unpublished remote branch.

- `swift-nio-ssh`: Wellz26/swift-nio-ssh 0.3.7, commit `d88989f3d3bb1dfb2a38ce4af598afbf7fc3095c` (Apache-2.0).
- `Citadel`: orlandos-nl/Citadel 0.12.1, commit `ae8562f895de06ccb86fdb1cbb65fd99c8976e12` (MIT).

Original Sources, Tests and license files are retained. All other dependency versions remain locked in the Xcode Package.resolved file.

## Local changes

NIOSSH:
- Custom public keys can declare host signature algorithm names separately from their wire encoding, with a backwards-compatible default.
- Client key exchange checks both the key's declared algorithms and received signature name against the negotiated host signature algorithm.
- Signature registration is independent of public-key registration, supporting SHA-256 and SHA-512 on the same RSA key type; uses the signatures lock.
- Removed the documentation-only DocC plugin dependency from Package.swift.

Citadel:
- Package.swift references the local sibling NIOSSH snapshot.
- The SFTP inbound handler rejects initialization and closes only the subsystem channel on SSH CHANNEL_FAILURE, instead of waiting forever for SFTP VERSION.

App-side RSA-SHA2 verification uses the existing Swift Crypto `_CryptoExtras` implementation with RFC 8332 PKCS#1 v1.5 signatures, a minimum 2048-bit modulus, and SHA-256/SHA-512 only. No SHA-1 host signature is registered by this compatibility configuration. Ed25519 and ECDSA remain enabled.

Regression coverage lives in the app's RSAHostKeyTests and PasswordConnectionTests; existing upstream test sources are preserved for further upstream maintenance.

Upstream formatting (including existing trailing whitespace) is retained to keep the snapshots comparable. Run whitespace checks on app-owned changes with `git diff --cached --check -- . ":(exclude)Vendor"`; do not bulk-reformat the upstream copies.
