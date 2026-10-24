# The `.sheafnote` backup format

Version 1. A `.sheafnote` file is a plain ZIP archive. You can open it with any unzip tool, and read it from any language with a ZIP library and a JSON parser. The reference implementation is `Packages/SheafnoteCore/Sources/SheafnoteCore/Archive/`.

Media type `application/x-sheafnote`, uniform type identifier `co.xanom.sheafnote.archive`, file extension `.sheafnote`.

## Container

- Standard ZIP, **store only** (compression method 0). Every entry is written uncompressed with a CRC-32. Sheafnote's own reader rejects compressed entries; repackage with "store" (`zip -0`) if you modify an archive.
- ZIP64 records are used automatically when the archive has more than 65 534 entries or any size or offset reaches 4 GiB.
- Entry names are UTF-8 (general purpose flag bit 11), relative, `/`-separated, with no empty, `.` or `..` components, no backslashes and no NUL. Readers must reject any other name.
- Writers produce deterministic bytes: entries in a fixed order, timestamps fixed at 1980-01-01 00:00, no extra attributes. Two exports of the same library at the same `createdAt` are byte-identical.
- No directory entries; paths are just names.

## Entries

| Entry | Content |
|---|---|
| `manifest.json` | Required. Format identification and counts. |
| `library.json` | Required. Every record (folders, notebooks, pages, elements, ...). |
| `ink/<pageID>.drawing` | The page's ink: the exact `PKDrawing.dataRepresentation()` bytes from PencilKit. Present when the page's `hasInk` is true. |
| `assets/<assetID>` | Raw bytes of an attached file (PDF, image, audio). Metadata is in `library.json` `assets`. |
| `richtext/<notebookID>.json` | A text document's rich text JSON, when the notebook's `hasRichText` is true. |
| `flashcards/<cardID>.front.png`, `.back.png` | The two card faces. |
| `saved-elements/<id>.drawing`, `<id>.thumbnail` | A saved element's ink (when `hasInk`) and thumbnail image. |

IDs in entry names are upper-case UUID strings, as `UUID.uuidString` prints them.

Entries are written in this order: `manifest.json`, `library.json`, then the blobs sorted by kind (notebook rich text, page ink, flashcards, saved elements, assets), each group sorted by ID. Readers must not depend on order.

## `manifest.json`

```json
{
  "format": "sheafnote-archive",
  "formatVersion": 1,
  "createdAt": "2026-10-23T15:30:00Z",
  "appVersion": "0.1.0",
  "scope": "library",
  "counts": { "folders": 3, "notebooks": 12, "pages": 340, "elements": 58, "assets": 4 }
}
```

- `format` must be exactly `sheafnote-archive`; anything else is not a Sheafnote archive.
- `formatVersion` is an integer. A reader that only knows versions up to N must refuse a file with a larger version ("made by a newer Sheafnote") and import nothing. Within a version, writers only ever **add** optional keys, so readers must ignore unknown keys and tolerate missing optional lists.
- `scope` is `library` (everything alive in the library, including the folder tree and saved elements) or `notebooks` (the chosen notebooks only; no folders, no saved elements).
- Dates are ISO 8601 UTC with second precision.

## `library.json`

One object with these lists. Every list may be absent (read as empty).

```json
{
  "folders": [], "notebooks": [], "pages": [], "elements": [], "assets": [], "outline": [],
  "bookmarks": [], "audioRecordings": [], "flashcards": [], "studyStates": [], "savedElements": []
}
```

Every record has an `id` (UUID string). References between records are plain id strings (never nested), and the archive must be closed: a reference to a record that is not in the archive makes the archive invalid, except where noted "optional".

### `folders[]`
`id`, `name`, `parentID` (optional; a missing or unknown parent means top level), `sortKey`, `isFavorite`, `colorName` (optional), `createdAt`, `modifiedAt`.

### `notebooks[]`
`id`, `title`, `kind` (`paged` | `whiteboard` | `text`), `folderID` (optional), `cover` (`{ "coverID": "tide", "version": 1 }`), `template` (`{ "kind": "ruledCollege", "version": 1 }`, the default for new pages), `paperSize` (`a4` | `letter` | `a5` | `square`), `orientation` (`portrait` | `landscape`), `paperColor` (`white` | `yellow` | `dark`), `scrollDirection` (`vertical` | `horizontal`), `isFavorite`, `isLocked`, `sortKey`, `pdfOutlineImported`, `hasRichText`, `createdAt`, `modifiedAt`.

### `pages[]`
`id`, `notebookID`, `sortKey` (see below), `width`, `height` (points, 1/72 inch), `templateOverride` (optional template object), `paperColorOverride` (optional), `backgroundAssetID` (optional, an `assets[]` id: the PDF or image drawn behind the ink), `backgroundPageIndex` (optional, zero-based page of the PDF), `strokeIDs` (ordered stroke ids, same order as the strokes in the drawing), `inkHash` (SHA-256 hex of the drawing bytes), `recognizedText`, `ocrInkHash`, `isInfinite`, `hasInk`, `createdAt`, `modifiedAt`.

Pages of a notebook are ordered by `sortKey`, ties broken by `id`.

### `elements[]`
Objects on a page (text boxes, images, stickers, tape, links, shapes).
`id`, `pageID`, `kind` (`text` | `image` | `sticker` | `tape` | `link` | `shape`), `x`, `y`, `width`, `height` (points, origin top-left of the page), `rotation` (as stored by the app, in radians), `zIndex`, `payload` (base64 of the kind's JSON payload, stored as written by the app; its `version` field says how to read it), `assetID` (optional), `createdAt`, `modifiedAt`.

### `assets[]`
`id`, `kind` (`pdf` | `image` | `audio` | `thumbnail`), `sha256` (hex of the bytes in `assets/<id>`), `byteCount`, `filename` (optional), `uti` (optional).
A reader must verify `sha256` and refuse the archive on a mismatch.

### `outline[]`
`id`, `notebookID`, `title`, `pageID` (optional), `pdfPageIndex` (optional), `parentID` (optional), `sortKey`, `source` (`user` | `pdf`).

### `bookmarks[]`
`id`, `notebookID`, `pageID`, `title` (optional).

### `audioRecordings[]`
`id`, `notebookID`, `assetID` (an `audio` asset), `title`, `startedAt`, `duration` (seconds), `timeline` (base64 of JSON mapping stroke ids to time offsets; contains page ids).

### `flashcards[]`, `studyStates[]`
Flashcard: `id`, `notebookID`, `deck`, `sourcePageID` (optional), `frontText`, `backText` (both optional); images are in `flashcards/`.
Study state: `id`, `flashcardID`, `ease`, `intervalDays`, `repetitions`, `lapses`, `dueAt`, `lastReviewedAt` (optional).

### `savedElements[]`
`id`, `name`, `category`, `width`, `height`, `hasInk`, `elements` (base64 of a JSON array of element values).

## Sort keys

`sortKey` is a base-62 string (`0-9A-Za-z`) compared as plain strings, used for order in a list. Sheafnote inserts between two neighbors by computing a string between their keys, so reordering never rewrites other items. Readers that only display an archive can sort by `sortKey` then `id`.

## What is not in an archive

- Items in Recently Deleted.
- Local-only data: recovered-page snapshots, search indexes (the recognized text per page is included), sync state, app settings, tool presets.
- Anything from outside the library: app lock settings, backup folder choice.

## Importing

Sheafnote imports an archive **as new copies**. It never overwrites or merges with what is already in the library:

1. Open the ZIP, read `manifest.json`, check `format` and `formatVersion`.
2. Read `library.json` and check the whole archive: unique ids, all references resolve, all files exist, every asset checksum matches. If anything is wrong, nothing is imported.
3. Store the attached files (deduplicated by SHA-256 against files already on the device).
4. Create every record with a **new id**. Ids that appear inside stored JSON (link targets, audio timelines) are rewritten to the new ids; strings that are not known ids are left alone.
5. Save once. A library-scope archive can be placed inside a new wrapper folder ("Backup 2026-10-23").

Original `createdAt` and `modifiedAt` dates are kept, so "last edited" survives a restore.

## Reading an archive without Sheafnote

```
unzip -l backup.sheafnote
unzip -p backup.sheafnote library.json | jq '.notebooks[] | {title, kind}'
unzip -p backup.sheafnote assets/<assetID> > book.pdf
```

Ink files are PencilKit `PKDrawing` data; load them with `PKDrawing(data:)` on iOS or macOS.

## Versioning rules for future changes

- Adding optional keys to a record, or a new optional list to `library.json`, or a new optional entry kind: no version bump.
- Renaming or removing a key, changing a type, or changing the meaning of a value: bump `formatVersion`. Older readers then refuse the file instead of misreading it.
