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

## Sync and CloudKit

Sync is our own layer on `CKSyncEngine` against the CloudKit private database of container `iCloud.co.xanom.sheafnote`. The local SwiftData store is not CloudKit-backed and stays the source of truth.

- **Zone and records.** One custom zone, `SheafnoteZone`. Record name is the row's UUID. Record types: `SNFolder`, `SNNotebook`, `SNPage`, `SNPageElement`, `SNAsset`, `SNOutlineEntry`, `SNBookmark`, `SNAudioRecording`, `SNFlashcard`, `SNStudyState`, `SNSavedElement`, `SNSetting`. Field name equals the Swift property name; relationships are plain UUID strings; common fields are `formatVersion`, `createdAt`, `modifiedAt`, `deletedAt`. Binary fields over 100 KB (and always `SNPage.inkData`, `SNAsset.data`) are `CKAsset`s. `PageRevision` and local-only properties never leave the device.
- **Forward compatibility.** The schema only grows. Unknown fields are ignored on read. A record with a higher `formatVersion` than the app knows is kept but never uploaded over.
- **Conflicts.** Fields you changed keep your value, others take the server's. A delete beats an edit unless a later restore says otherwise. Page ink merges per stroke (`StrokeMerger`, three-way against the last synced version). If the ink cannot be merged, your version stays live and the iCloud version goes to Settings > iCloud Sync > Recovered Pages for 30 days. Your pre-merge version is always saved there too.
- **Deletes.** Soft deletes sync as `deletedAt`. A row is purged, and its CloudKit record deleted, only after 30 days in Recently Deleted. A server-side deletion never removes a row that is alive on this device; it is uploaded again.
- **Accounts.** Signing out or switching accounts never deletes local data. After a switch the app asks whether to upload this device's notebooks to the new account. Turning sync off is local-only mode.
- **Code.** Logic is in `Packages/SheafnoteCore/Sources/SheafnoteCore/Sync` and is tested against `InMemoryCloud` (two simulated devices, offline edits, account events). The CloudKit adapter is `App/Features/Sync/CKSyncEngineTransport.swift`.

**Human steps and limits**
- Before any TestFlight or App Store build, deploy the CloudKit schema to Production in the CloudKit Console (Development schema is created on first save from a signed build).
- Automated tests cannot reach iCloud. Real CloudKit behavior (`CKSyncEngineTransport`) is not verified by agents: test with two devices or two simulators signed in to the same iCloud account, using signed builds and `SHEAFNOTE_CLOUDKIT_IN_SIMULATOR=1`. Unsigned simulator builds have no iCloud entitlement, so there sync shows "Not signed in".

## Privacy

No tracking, no third-party code, no network calls except iCloud sync. See `App/PrivacyInfo.xcprivacy`.

## License

MIT, see `LICENSE`.

## Notes for contributors

- `App/Resources/Localizable.xcstrings` is refreshed after a build with
  `xcrun xcstringstool sync App/Resources/Localizable.xcstrings --stringsdata <DerivedData>/.../Sheafnote.build/Objects-normal/arm64/*.stringsdata`.
- `xcodebuild test` attaches a debugger, so macOS Developer Mode must be on (`sudo DevToolsSecurity -enable`).
- Regenerate the app icon with `swift scripts/make-icon.swift`.
