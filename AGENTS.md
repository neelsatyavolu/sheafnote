# Agent Instructions

Sheafnote: handwritten notes app for iPad and iPhone (SwiftUI + PencilKit, iOS 26, Swift 6).

## Commands
| Task | Command |
|------|---------|
| Core tests (one suite) | `swift test --package-path Packages/SheafnoteCore --filter CoverTests` |
| Core tests (all, ~25s) | `swift test --package-path Packages/SheafnoteCore` |
| Regenerate Xcode project | `xcodegen generate` |
| Release to TestFlight | `scripts/testflight.sh` |

## Testing
- Never run tests through Xcode: no `xcodebuild test`, simulators, `AppTests/`/`AppUITests/` runs, or `scripts/verify.sh`. Cold builds take many minutes.
- Verify with the core package tests above.
- Put testable logic in `Packages/SheafnoteCore` so it can be covered there.
- App-only changes (UIKit, SwiftUI, gestures) are checked by the user on device; say so instead of claiming they're tested.

## Layout
| Path | Contents |
|------|----------|
| `Packages/SheafnoteCore/` | Pure logic, no UIKit: models, stores, ink, sync, archive, recognition |
| `App/Interfaces/` | Extension points (`FeatureModule`, `ToolRegistry`, `PageLayers`, ...) features plug into |
| `App/Features/<Feature>/` | One folder per feature; registers itself via `FeatureModule` |
| `App/Shell/` | App bootstrap, module registration (`FeatureModules.swift`), UI test seeds |
| `site/` | sheafnote.com website |

## Key Conventions
- `Sheafnote.xcodeproj` is generated from `project.yml` and gitignored; edit `project.yml`, never the project.
- `SheafnoteCore` must not import UIKit or SwiftUI.
- User-facing strings go in the feature's own `Resources/<Feature>.xcstrings`, referenced with `tableName:`.
- Interactive views get an `accessibilityIdentifier` (`editor.undo`, `settings.editor.doubleTap`, ...).
- The notebook has one undo manager (`NotebookSession.undoManager`); PencilKit's own undo is disabled.
- Visual work follows `DESIGN.md`.

## Releasing
1. Bump `MARKETING_VERSION` in `project.yml`.
2. Commit as `chore: bump version to X.Y.Z`.
3. Run `scripts/testflight.sh` (credentials load from 1Password via the gitignored `scripts/testflight.local.sh`).
4. Check the script's exit code; don't pipe it through `tail`.

## External References
| Need | File |
|------|------|
| Build setup, sync/CloudKit design | `README.md` |
| Visual design | `DESIGN.md` |
| `.sheafnote` backup format | `docs/FORMAT.md` |
| Product spec and plan | `docs/superpowers/specs/2026-10-23-sheafnote-design.md`, `docs/superpowers/plans/2026-10-23-sheafnote-plan.md` |
