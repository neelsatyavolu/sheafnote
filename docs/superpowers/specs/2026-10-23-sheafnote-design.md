# Sheafnote: design

Date: 2026-10-23
Status: approved by owner 2026-10-23

## Intent

A free, open-source handwritten-notes app for iPad and iPhone that matches GoodNotes 6 feature for feature (minus AI) and looks like it, but is built from stock iOS parts so it feels more native. Notes stay on the owner's devices and in the owner's own iCloud. There are no accounts, no subscriptions, no limits on notebooks or pages, no ads, no analytics.

The owner's words: "a goodnotes alternative that has the same look (however more native) and all the features (non-AI)", and notes should sync between iPad and iPhone.

The name "Sheafnote" (a sheaf is a bundle of papers) was checked on 2026-10-23: no App Store app, GitHub repo or website uses it. Bundle ID `co.xanom.sheafnote`, iCloud container `iCloud.co.xanom.sheafnote` (my calls).

## Goals

- Every non-AI feature of GoodNotes 6 listed under "Features" below works on iPad and iPhone.
- Writing with Apple Pencil feels as good as GoodNotes: low latency, pressure, palm rejection, double-tap and squeeze to switch tools.
- Notebooks, folders and pages sync between the owner's devices through iCloud (CloudKit private database). No server of ours.
- Works fully offline. Sync catches up when a connection returns.
- No artificial limits anywhere.
- Open source (MIT license, my call), buildable by anyone with Xcode.

## Non-goals

- AI features of any kind (no AI summaries, no "Ask Goodnotes", no AI math or spellcheck beyond what iOS itself provides).
- Real-time collaboration, shared links, or anything else that needs a server we run.
- A template or sticker marketplace.
- Android, Windows, web. A Mac Catalyst or "Designed for iPad" build on Mac is allowed if it comes free, but nobody is testing for it.
- Reading `.goodnotes` files. Users can export PDFs from GoodNotes and import those.

## Anti-goals (would count as failure even if it works)

- Ink that lags, skips or feels worse than GoodNotes or Apple Notes.
- Losing notes. A sync conflict, crash, or bad migration must never destroy a page. Data safety beats every other feature.
- A UI that looks like a cheap web clone: custom-drawn buttons, non-standard sheets, fake blur. Use system controls, SF Symbols, Liquid Glass toolbars.
- Any network call other than iCloud sync. No telemetry, crash reporters, or third-party SDKs that phone home.
- Paywalls, upsell screens, or "pro" flags left in the code.

## Constraints

- Swift and SwiftUI, Xcode 27 (installed on the owner's Mac). UIKit only where SwiftUI cannot do the job (PencilKit canvas hosting, some gesture work).
- Minimum OS: iOS/iPadOS 26 (my call; gets current SwiftUI, Liquid Glass and newer PencilKit inks without back-compat work).
- One universal app target for iPhone and iPad.
- Signing and the CloudKit container use the owner's paid Apple developer team.
- No third-party dependencies unless a feature truly cannot be built with Apple frameworks. If one is needed, it must be open source and make no network calls.
- Owner's testing rules apply: test-first for model, sync merge, shape recognition, templates and export logic; aim for 80% coverage of non-UI code; XCUITest for the main flows (create notebook, write, add page, search, export).

## Look and feel

GoodNotes 6 is the reference for layout and workflow. Native iOS controls do the actual rendering, and the visual identity is our own (see Owner decisions). The owner's personal "Machine & Ink" design system does not apply here, because the owner asked for the GoodNotes look.

**Library (home)**
- iPad: a `NavigationSplitView`. The sidebar has Documents, Favorites, Search, Recently Deleted, and the folder tree. The main area is a grid of notebook covers (cover art, title underneath, last-edited date), with folders shown as folder tiles. A toolbar holds "+ New" (notebook, whiteboard, text document, folder, import), sort, a grid/list toggle and Select.
- iPhone: the same screens stacked in a `NavigationStack`, with a two-column cover grid.
- Context menus on covers: rename, change cover, duplicate, move, favorite, export, delete.

**New notebook sheet**
- A title field, a cover carousel (about 20 built-in covers: solid colors and simple patterns), and a paper carousel grouped by type: blank, ruled (narrow/college/wide), grid (several sizes), dotted, Cornell, music staff, and planner pages (daily, weekly, monthly, to-do). Paper color can be white, yellow or dark, with portrait or landscape orientation. Sizes: A4, US Letter, A5, plus a square size for whiteboards.

**Editor**
- Top bar, laid out like GoodNotes 6. Left side: back, page thumbnails, search in notebook, bookmark, share/export. Center: the tool row (pen, eraser, highlighter, shapes, lasso, element/image, text, laser pointer, plus "more" for tape and zoom window). Right side: undo, redo, more (add page, page template, scroll direction, presentation mode, record audio).
- The tool row is our own SwiftUI toolbar built from system controls, not Apple's `PKToolPicker`, because the owner asked for the GoodNotes layout. That means we own tool state, presets and Pencil double-tap/squeeze handling (via `UIPencilInteraction`).
- A second slim row under the tool row shows the selected tool's options: ink type, 3 or more color presets, 3 width presets, and a "+" for custom color and width. Tapping an active preset opens its editor. This matches GoodNotes's preset row.
- Pages appear on a gray canvas with a soft shadow. Pinch to zoom. Scroll vertically (continuous) or horizontally (page by page). On iPhone the tool row moves to a bottom toolbar.
- Tabs: on iPad, open notebooks appear as tabs across the top, like GoodNotes 6. Split View and Stage Manager allow two windows side by side.

## Features (the full list, grouped into build phases)

Each phase ships as a working app before the next phase starts.

### Phase 1: library, writing, sync

- Library: folders (nested), notebooks, favorites, sort (name/created/modified), grid and list, Recently Deleted (kept 30 days, restorable), multi-select move/delete.
- New notebook with covers, paper templates, sizes, colors, orientation. Change a page's template later.
- Pen tool with PencilKit's inks (pen, fountain pen, monoline, pencil, crayon, watercolor); pressure sensitivity; color and width presets.
- Highlighter with a "draw straight line" option.
- Eraser: whole-stroke and partial, with sizes, an "erase highlighter only" option, and an option to switch back to the previous tool after erasing (GoodNotes has both).
- Undo and redo per notebook.
- Pages: add (before/after/at end), duplicate, delete, reorder by drag in the thumbnail grid, go to page.
- Apple Pencil double-tap and squeeze tool switching. Option: draw with finger or Pencil only.
- iCloud sync of everything above, plus local-only mode if the user is signed out of iCloud.

### Phase 2: PDFs, objects, smarter ink

- Import PDF (Files, share sheet, drag and drop) as a new notebook, or insert its pages into an existing one. Import images as pages.
- Mark up PDF pages like any other page. The PDF stays the background; ink sits on top.
- Export a notebook or selected pages as PDF (with or without page backgrounds) or as images. Share via the share sheet.
- Lasso: freeform select of ink, text and images. Move, resize, rotate, recolor, change width, copy/cut/paste/duplicate, delete, take a screenshot of the selection, convert handwriting to text (on-device Vision). Options for what the lasso picks up (handwriting, images, text).
- Shapes tool: a drawn stroke becomes a clean line, arrow, rectangle, ellipse/circle, triangle, polygon or arc. Also in pen mode: draw and hold to snap. Shapes have fill and outline colors.
- Text boxes: font, size, color, bold/italic/underline, alignment, background color, resize, move.
- Images: insert from Photos, Files or camera; crop, resize, rotate, move.
- Zoom window: the GoodNotes magnified writing strip with auto-advance and margin controls.

### Phase 3: finding things

- Search across the whole library and inside a notebook: handwriting (indexed on-device with Vision), typed text, PDF text, notebook and folder titles. Results show page thumbnails with hits highlighted.
- Bookmarks on pages, with a bookmarks list in the thumbnail view.
- Outline: user-made outline entries plus the PDF's own outline. Tap to jump.
- Links: link a lasso selection or text to another page, another notebook, or a URL.
- Scroll direction setting per notebook (vertical continuous, or horizontal paged).

### Phase 4: GoodNotes 6 extras

- Elements and stickers: a built-in sticker set (simple open-licensed shapes, arrows, tabs, washi-tape strips), plus "save lasso selection as element" for reuse.
- Study tape: cover ink or text with tape that you tap to reveal or hide. A "hide all / show all" toggle.
- Laser pointer (dot and fading trail), for presenting.
- Presentation mode: on an external display or AirPlay, show only the page without any UI. Options to hide toolbars, show the laser pointer, show the zoom window.
- Audio recording while writing. Playback can jump to the moment a stroke was written: tap a stroke during playback mode to seek. Recordings belong to the notebook.
- Flashcards: make cards from page content (front and back regions or a lasso selection), study them with simple spaced repetition (a basic SM-2 style schedule, no AI).
- Whiteboards: a notebook type with one infinite canvas instead of pages.
- Text documents: a notebook type for typed notes (rich text with headings, lists, checklists, images), like GoodNotes 6 text docs.
- App lock: Face ID / Touch ID / passcode for the whole app, optionally per notebook.
- Backup: export and import the whole library or one notebook as a `.sheafnote` file (a zip holding JSON plus raw ink and asset files, documented in the repo so other apps can read it). Optional automatic backup to a folder the user picks in Files.

## How it's built

These are my calls unless marked otherwise. The builder can change them with a reason.

**Ink engine: PencilKit.** It gives Apple's own low-latency rendering, pressure, palm rejection, Pencil double-tap and squeeze, and the newer inks (fountain pen, monoline, watercolor). Custom tools (lasso with recolor/resize, shape snapping including draw-and-hold, straight highlighter, an eraser that can skip pen strokes and erase only highlighter, tape, laser) work on `PKDrawing.strokes` directly. Draw-and-hold needs its own touch tracking alongside the canvas, since PencilKit doesn't expose the stroke while it's still being drawn. They don't rely on PencilKit's built-in lasso, which offers no API to read the selection. If PencilKit turns out unable to deliver a required feature with acceptable feel, stop and raise it with the owner before writing a custom Metal ink engine.

**Page layers, bottom to top:** paper color, template pattern (drawn as vectors, not images), PDF page (PDFKit), images and stickers, text boxes, ink (PKCanvasView), tape, then transient overlays (laser, lasso, zoom window). Ink sits above images and text, matching GoodNotes.

**Storage: a local SwiftData store (not CloudKit-backed). Sync: our own layer on `CKSyncEngine` against the CloudKit private database.** (My call, changed after review. SwiftData's built-in CloudKit sync gives no conflict callback, merges last-to-server-wins, can't toggle between synced and local-only, and resets when the iCloud account changes. With `CKSyncEngine` we see both versions on a conflict and decide what happens.)
- Models (rough): `Folder`, `Notebook` (kind: paged, whiteboard, text), `Page`, `PageElement` (text, image, sticker, tape, link), `Asset` (PDF and image bytes), `OutlineEntry`, `Bookmark`, `AudioRecording`, `Flashcard`, `StudyState`.
- Ink is stored per page as `PKDrawing.dataRepresentation()` and synced as a `CKAsset` on that page's record, so each page syncs on its own. A big notebook never syncs as one blob.
- Page order uses fractional sort keys (a string or double between neighbors), so reordering on two devices doesn't rewrite every page.
- Conflicts: when the server reports a newer version of a page we also changed, first try a per-stroke merge (strokes carry stable IDs in our page record; union both sides' additions and apply both sides' deletions). If merging isn't possible, keep both versions: ours wins and theirs goes into a local "Recovered" area for 30 days. A sync conflict must never silently drop a page's ink.
- Signing out of iCloud or switching accounts never deletes local data. Local-only mode is just "sync engine off".
- Deletes are soft (Recently Deleted) and only purged after 30 days.
- The CloudKit schema can only grow once deployed to production: no renames, removals or type changes, and older builds on another device read the same records. Record fields can only be added, unknown fields must be ignored, and records carry a format version. Deploy the schema to production before any TestFlight or App Store build. The local SwiftData store migrates normally through versioned schemas.
- Build and test sync early in Phase 1 (two simulators or devices, offline edits, account sign-out), not at the end.

**Search index:** OCR runs in the background on changed pages (Vision text recognition on a rendered page image, on-device only). The text is stored on the `Page` so it syncs too, and the other device doesn't need to re-OCR. Handwriting search covers whatever languages Vision supports, with English as the one that must work well (my call).

**Templates:** described in code (line spacing, margins, grid size, colors), so they're crisp at any zoom and export cleanly to PDF. Planner templates are composed from the same primitives.

**Export:** PDF via PDFKit/Core Graphics. Draw each page's layers into a PDF context. Ink goes in as vector paths where practical, otherwise as high-resolution images.

**Project layout (suggested):** an Xcode project at `~/Documents/GitHub/sheafnote` with an app target, a local Swift package for the core (models, templates, shape recognition, export, `.sheafnote` format) so it can be unit-tested without the simulator, and a UI test target. Files stay small and focused, per the owner's coding rules.

## Left to the builder

- Exact visual details: spacing, cover art, icon, colors, matching GoodNotes closely without copying its assets. Draw our own covers, stickers and icon. Do not copy GoodNotes artwork, trademarks or templates.
- The shape-recognition approach (a simple geometric fit is fine).
- How the zoom window, laser trail and audio-to-stroke timing work internally.
- Performance targets, as long as writing feels instant and a 500-page PDF opens in a couple of seconds on a recent iPad.
- Order of work inside a phase.

## Owner decisions (2026-10-23)

- **Public.** The goal is a free App Store listing and a public GitHub repo. So the layout and workflow follow GoodNotes, but the visuals are our own: own icon, covers, colors and naming, no GoodNotes screenshots or assets, nothing that reads as a copy under App Store guideline 4.1. Ship with a privacy manifest, VoiceOver labels on all controls, Dynamic Type in the library and menus, and English-only UI strings kept in a String Catalog so translation can come later.
- **Apple's inks.** Use PencilKit's own inks (pen, fountain pen, monoline, marker, watercolor, crayon, pencil) under their Apple names. No custom ink engine.
- **Owner's test device:** iPad Air (4th gen, A14) with Apple Pencil (2nd gen). Double-tap must work; squeeze and hover are nice-to-haves for newer Pencils and get no special effort. Performance targets are measured on this iPad. iOS 26 minimum stays (this iPad runs it).

## Open items for the owner

- Signing team: Ramakrishna Satyavolu, team ID `VTQW687WBQ` (owner, 2026-10-23). It is not yet signed into Xcode on the owner's Mac; device builds will need it added in Xcode > Settings > Accounts or the App Store Connect API key from 1Password.
- When to make the GitHub repo public. Not needed until Phase 1 is done.
