# Sheafnote

## Testing

- Do not run tests through Xcode or `xcodebuild test` (no simulator runs, no UI tests, no `scripts/verify.sh`). A cold build plus simulator boot takes many minutes.
- Use the quick code tests instead: `swift test --package-path Packages/SheafnoteCore`.
- Put logic that needs testing in `SheafnoteCore` so it can be covered there. App-only changes (UIKit, SwiftUI) are checked by the user on device.

## Releasing

- Bump `MARKETING_VERSION` in `project.yml`, commit as `chore: bump version to X.Y.Z`, then run `scripts/testflight.sh` to archive and upload to TestFlight.
