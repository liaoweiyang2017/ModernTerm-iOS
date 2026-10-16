# ModernTerm iOS 0.2.0 monitoring validation

Date: 2026-10-16 (Europe/Copenhagen)

- iPhone 18 Pro / iOS 27.0 simulator: **11 tests passed**.
- Final simulator build (ad-hoc signed) and Release iOS device build (unsigned arm64): passed. Updated app installed on iPhone and iPad simulators in normal mode, without preview arguments.
- Multi-server Overview entry and sheet verified in native iPhone UI.
- Metrics fixtures cover CPU/per-core deltas excluding guest double-counting, remote-uptime rate denominators, memory/swap, interface filtering, disk throughput/IOPS, TCP counters, GPU/Docker/process parsing, temperatures, first samples, malformed fields, reboot/counter resets and unsupported platforms.
- Real ephemeral localhost SSH validates a monitoring-only connection (no PTY or SFTP channel), macOS platform detection, on-demand PTY, SFTP upload/download/edit/conflict/delete, pinned host-key rejection and Keychain behavior. No user servers or credentials accessed.
- Collector script passes POSIX shell syntax validation. Linux `/proc`, GPU and Docker values were validated with fixtures, **not with a live Linux/GPU/Docker host**.
- Native iPhone monitoring UI inspected in Device Hub using the explicitly labeled Debug preview with simulated data: compact cards, trend charts and per-core grid. Preview creates no network connection and is excluded from Release builds.
- 60 history samples per connection, maximum 8 connections, sequential polling with a 256 KiB response limit. Backgrounding disconnects and stops polling.
- Optional metrics require existing server commands/permissions. No sudo, installation, Docker mutations or host-permission changes.

## Previous 0.1.0 baseline

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
- Native iPad Pro 13-inch / iPadOS 27.0 simulator: sidebar and detail layout visually verified; simulator app installed.
- Native iPhone UI inspected through Xcode Device Hub: application name, home layout, add-server entry, Settings, palette/font/background policy controls.
- Temporary test SSH server, private keys and fixture source removed after testing. Test bundle removed from delivered simulator app.
- No real user server, desktop credential store or iCloud files accessed.

Not verified: physical device installation, password authentication against a live server, encrypted RSA private keys on a real device, long-duration/large transfer stress, App Store distribution. Dependencies provide password and key authentication; the network integration test specifically covers unencrypted Ed25519.
