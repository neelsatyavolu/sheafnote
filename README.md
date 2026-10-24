# Sheafnote

A free, open-source handwritten notes app for iPad and iPhone. Notebooks, folders, Apple Pencil ink, and iCloud sync between your own devices. No accounts, no subscriptions, no ads, no analytics, no AI.

Status: early. The library (folders, notebooks, covers, paper templates, Recently Deleted) is in place; the page editor and the other features are built by separate units, see `docs/superpowers/plans/`.

## Build

Requires Xcode 27, iOS/iPadOS 26, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
xcodegen generate                                   # creates Sheafnote.xcodeproj (gitignored)
swift test --package-path Packages/SheafnoteCore    # core tests, run on the Mac
xcodebuild -project Sheafnote.xcodeproj -scheme Sheafnote \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath .derived/dev CODE_SIGNING_ALLOWED=NO build
scripts/verify.sh <label>                           # generate, core tests, build, app tests on a temporary simulator
```

To run on a device, set your own team in `project.yml` (`DEVELOPMENT_TEAM`) and the iCloud container in `App/Sheafnote.entitlements`.

## Layout

- `App/`: the app target (SwiftUI). `Interfaces/` holds the extension points features plug into.
- `Packages/SheafnoteCore`: pure logic with no UIKit (models, templates, covers, stores, recognition). Tests run with `swift test`.
- `AppTests/`, `AppUITests/`: unit and UI tests.

## Privacy

No tracking, no third-party code, no network calls except iCloud sync. See `App/PrivacyInfo.xcprivacy`.

## License

MIT, see `LICENSE`.

## Notes for contributors

- `App/Resources/Localizable.xcstrings` is refreshed after a build with
  `xcrun xcstringstool sync App/Resources/Localizable.xcstrings --stringsdata <DerivedData>/.../Sheafnote.build/Objects-normal/arm64/*.stringsdata`.
- `xcodebuild test` attaches a debugger, so macOS Developer Mode must be on (`sudo DevToolsSecurity -enable`).
- Regenerate the app icon with `swift scripts/make-icon.swift`.
