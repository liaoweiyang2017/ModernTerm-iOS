# Android third-party components

The app does not include Termux or GPL terminal app code. App-owned sources keep the repository's existing proprietary terms. Dependencies are used under their respective licenses; this is not a relicensing of them.

- SSHJ 0.41.2 — Apache 2.0, https://github.com/hierynomus/sshj
- AndroidX / Jetpack Compose / Material3 / WebKit — Apache 2.0, https://developer.android.com/jetpack/androidx
- Kotlin and kotlinx.coroutines — Apache 2.0, https://github.com/JetBrains/kotlin and https://github.com/Kotlin/kotlinx.coroutines
- Bouncy Castle provider/PKIX/util 1.84 — MIT-style Bouncy Castle license, https://www.bouncycastle.org/licence.html
- SLF4J 2.0.17 — MIT, https://www.slf4j.org/license.html
- xterm.js 5.5.0 and addon-fit 0.10.0 — MIT; license texts packaged beside the terminal assets.
- asn-one 0.6.0 — Apache 2.0, https://github.com/hierynomus/asn-one. See the resolved Gradle dependency report for exact runtime components.
- esbuild 0.25.5 — MIT, build-time only. Rebuild bundled terminal assets from android/terminal with the committed pnpm lockfile; target Chrome 70 syntax for older Android 10 WebViews.
- Test tools JUnit, AndroidX Test and Paramiko are not included in the release APK.

Full common license texts are packaged in app/src/main/assets/licenses. iOS-owned palettes retain Resources/PaletteProvenance.json attribution; monitor.sh is generated from Sources/ServerMetrics.swift by scripts/sync_shared.py.
