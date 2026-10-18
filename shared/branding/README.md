# Mobile icon alignment

Source: [Modernterm desktop artwork](https://github.com/liaoweiyang2017/Modernterm/blob/1e08e044a587fd7a87c9492c015aab1ec596aa9a/assets/Modernterm.png), commit `1e08e044a587fd7a87c9492c015aab1ec596aa9a` (desktop 0.5.6). This is the existing 0.5.3 artwork retained by that latest release; no icon was redrawn.

Original PNG SHA-256: `11bc4f580d716c9fbfd546ad425cc7e664b28a6438d6006affa4b9b4570c7cf4`. The original alpha PNG is retained here. The two mobile application icons use identical 1024×1024 RGB PNGs, composited onto #111827 for iOS's opaque-icon requirement; artwork geometry and colors are otherwise preserved.

Mobile version remains 0.2.3, build/versionCode 6.

Regenerate the iOS RGB icon with `xcrun swift ios/Scripts/build_app_icon.swift shared/branding/Modernterm.png ios/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`, then copy that file to `android/app/src/main/res/drawable/app_icon.png`.
