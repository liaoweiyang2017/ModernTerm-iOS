# ModernTerm iOS 0.1.0 validation

Date: 2026-10-16 (Europe/Copenhagen)

- Xcode 27.1, iOS SDK 27.1; deployment target iOS/iPadOS 17.0.
- Generic iOS Simulator build: passed (ad-hoc signed with Keychain entitlements).
- Generic iOS device build: passed; verified Mach-O arm64. This output is **unsigned** and is not an installable/distributable IPA.
- iPhone 18 Pro / iOS 27.0 simulator: 6 tests, all passed.
  - Server validation, Codable roundtrip and credential separation.
  - Shell argument quoting and path joining.
  - 18 unique palettes with complete ANSI sets.
  - iOS Keychain create/read/update/delete using a disposable test account.
  - Real localhost SSH Ed25519 authentication, PTY input/output, SFTP upload/download byte comparison, UTF-8 remote edit/save, conflict rejection and deletion.
  - Changed host key rejection before authentication, with no trust override prompt.
- Native iPhone UI inspected through Xcode Device Hub: application name, home layout, add-server entry, Settings, palette/font/background policy controls.
- Temporary test SSH server, private keys and fixture source removed after testing. Test bundle removed from delivered simulator app.
- No real user server, desktop credential store or iCloud files accessed.

Not verified: physical device installation, password authentication against a live server, encrypted RSA private keys on a real device, long-duration/large transfer stress, App Store distribution. Dependencies provide password and key authentication; the network integration test specifically covers unencrypted Ed25519.
