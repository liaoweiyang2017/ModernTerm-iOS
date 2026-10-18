# ModernTerm for iOS / iPadOS

The SwiftUI/UIKit application, Xcode project, resources, tests, and pinned Swift SSH dependencies live in this directory. Android is maintained separately in [`../android/`](../android/README.md).

See the main [English README](../README.md) or [中文说明](../README_CN.md) for features, installation, encrypted connection transfer, and platform limitations.

## Build

Run these commands from this directory:

```sh
xcodegen generate
xcodebuild -project ModerntermIOS.xcodeproj -scheme ModerntermIOS \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$HOME/Library/Caches/ModernTerm-build" \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build
```

Open `ModerntermIOS.xcodeproj` in Xcode for device signing and simulator selection. `project.yml` is the source of project configuration. After editing it, regenerate the project with XcodeGen. The committed `Package.resolved` retains the dependency lock.

## Tests and resources

- Run `ModerntermTests` and `ModerntermUITests` in Xcode, or use `xcodebuild test` with an available simulator.
- Run integration scripts such as `python3 Scripts/password_integration.py` from this directory, using an isolated Python environment with their required dependencies. They create disposable fixtures in `Tests/`; these files remain ignored by Git.
- Shared `.term` test vectors are referenced from `../shared/term-transfer/`; do not duplicate them here.
- Android's monitoring script and palette copies are checked from the repository root with `python3 android/scripts/sync_shared.py --check`.
- Dependency patches: [Vendor/README.md](Vendor/README.md). Historical iOS validation: [VALIDATION.md](VALIDATION.md). Repository-wide acceptance records: [../specs/](../specs/).

Builds and tests run locally; GitHub Actions is disabled.
