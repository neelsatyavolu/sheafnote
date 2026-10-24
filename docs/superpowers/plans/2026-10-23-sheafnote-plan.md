# Sheafnote: implementation plan

Date: 2026-10-23
Spec: `docs/superpowers/specs/2026-10-23-sheafnote-design.md` (read it first; this plan is binding where it is more specific).

This plan lets 10 work units build the app in parallel without talking to each other. Rules that make that work:

1. **One owner per path.** Section 2 lists every folder/file and its unit. Never edit a path you do not own. If you need something from another unit, use the interface in section 3. If the interface is missing something, build an adapter inside your own folder and report it in your summary; do not change the interface (integrators extend interfaces additively).
2. **Foundation defines every cross-unit interface** (section 3) as real, compiling code in `App/Interfaces/` and `Packages/SheafnoteCore`. Later units only add files in their own folders.
3. **Units plug in through `FeatureModule`** (3.1). Foundation creates a stub `<Unit>Feature.swift` in each unit's folder and a central list in `App/Shell/FeatureModules.swift` that already names all of them, so nobody edits a shared file.
4. **Config files are foundation-owned and pre-populated for all units** (`project.yml`, Info.plist keys, entitlements, privacy manifest, document types). Later units never touch them.
5. **Strings:** each unit owns its own String Catalog table `App/Features/<Unit>/Resources/<UnitName>.xcstrings` and uses `String(localized: "key", table: "<UnitName>")` / `Text("key", tableName: "<UnitName>")`. Foundation owns `Localizable.xcstrings` (shell, library, settings). Table names: `Library`, `Editor`, `Sync`, `PdfIO`, `InkTools`, `Elements`, `Search`, `Present`, `AudioStudy`, `DocTypes`.
6. **Assets:** each unit may own an asset catalog `App/Features/<Unit>/Resources/<Unit>.xcassets` (names prefixed with the unit). Foundation owns `App/Resources/Assets.xcassets` (AppIcon, AccentColor).

## 1. Fixed decisions and commands

Repo `/Users/neel/Documents/GitHub/sheafnote`, branch `main`. Swift 6 language mode, Xcode 27, iOS/iPadOS 26.0 minimum, one universal app target. Bundle ID `co.xanom.sheafnote`, iCloud container `iCloud.co.xanom.sheafnote`, `DEVELOPMENT_TEAM VTQW687WBQ`, simulator builds only with `CODE_SIGNING_ALLOWED=NO`. No third-party dependencies, no network except CloudKit, no analytics, no AI. Look: GoodNotes 6 layout from native controls, own identity (own covers, colors, icon, stickers; never copy GoodNotes assets or names). "Machine & Ink" does not apply.

Commands (replace `<label>` with your unit label; `.derived/` and `Sheafnote.xcodeproj` are gitignored):

```bash
# regenerate project (after adding files, or after pulling)
cd /Users/neel/Documents/GitHub/sheafnote && xcodegen generate

# core tests (Mac, no simulator)
swift test --package-path Packages/SheafnoteCore
swift test --package-path Packages/SheafnoteCore --enable-code-coverage   # coverage check

# app build (simulator)
xcodebuild -project Sheafnote.xcodeproj -scheme Sheafnote \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .derived/<label> CODE_SIGNING_ALLOWED=NO build

# own simulator for app + UI tests
UDID=$(xcrun simctl create sheafnote-<label> "iPad Air 13-inch (M4)" com.apple.CoreSimulator.SimRuntime.iOS-26-5)
# if that fails: xcrun simctl list devicetypes | grep -i ipad ; xcrun simctl list runtimes
xcodebuild -project Sheafnote.xcodeproj -scheme Sheafnote -destination "id=$UDID" \
  -derivedDataPath .derived/<label> CODE_SIGNING_ALLOWED=NO test            # all tests
#   add -only-testing:SheafnoteTests/<Unit>   or   -only-testing:SheafnoteUITests/<Unit>UITests
xcrun simctl delete $UDID        # when done
```

Foundation also adds `scripts/verify.sh <label>` that runs: xcodegen, `swift test`, build, and app unit tests on a temporary simulator it creates and deletes. Every unit runs it before finishing.

Git: unit branch `unit/<label>` in its own worktree (`git worktree add ../sheafnote-<label> -b unit/<label>`), conventional commits, no attribution, never push, no remote. Foundation, editor and sync commit as described in section 6.

## 2. Folder ownership

Package layout: ONE library target `SheafnoteCore` and ONE test target `SheafnoteCoreTests`, so `Package.swift` is written once by foundation. Core sources are `Packages/SheafnoteCore/Sources/SheafnoteCore/<Area>/`, tests are `Packages/SheafnoteCore/Tests/SheafnoteCoreTests/<Area>/`. Core imports Foundation, CoreGraphics, SwiftData, CryptoKit, Vision, CloudKit, PDFKit only; never UIKit/SwiftUI/PencilKit/AppKit. Platforms iOS 26 and macOS 26.

App layout: `App/` (target `Sheafnote`), `AppTests/<Unit>/` (target `SheafnoteTests`), `AppUITests/` (target `SheafnoteUITests`).

| Path | Owner |
|---|---|
| `project.yml`, `Package.swift`, `.gitignore`, `scripts/`, `App/Info.plist`, `App/Sheafnote.entitlements`, `App/PrivacyInfo.xcprivacy`, `README.md`, `LICENSE` (MIT), `docs/archive-format.md` stub | foundation |
| `App/SheafnoteApp.swift`, `App/Shell/**` (root view, `AppDelegate`, `FeatureModules.swift`, `AppServices`, scene handling) | foundation |
| `App/Interfaces/**` (all cross-unit protocols and registries, section 3) | foundation |
| `App/Features/Library/**`, `App/Features/NewNotebook/**`, `App/Features/Settings/**` (scaffold, section registry host, General section) | foundation |
| `App/Resources/**` (`Localizable.xcstrings`, `Assets.xcassets`, covers art code) | foundation |
| `Packages/SheafnoteCore/.../Models/**`, `Schema/**`, `Templates/**`, `Covers/**`, `Recognition/**`, `Geometry/**`, `Ordering/**`, `Ink/**` (StrokeRecord, StrokeIdentity), `Elements/Payloads/**`, `Store/**` (library/page/revision/element-library stores) | foundation |
| `AppUITests/Support/**` (launch helpers, seeds) | foundation |
| `App/Features/Editor/**` (chrome, canvas, tools pen/highlighter/eraser, navigator, undo, tabs, selection transform engine, page renderer, `EditorFeature.swift`) | editor |
| `AppTests/Editor/**`, `AppUITests/EditorUITests.swift` | editor |
| `App/Features/Sync/**`, `Packages/.../Sync/**` (record mapper, coordinator, StrokeMerger, conflict policy, CKSyncEngine adapter, sync settings section), tests mirrored | sync |
| `App/Features/PdfIO/**`, `Packages/.../PDF/**`, `Export/**`, `Archive/**` | pdf-io |
| `App/Features/InkTools/**` (lasso, shapes, draw-and-hold, straight highlighter), `Packages/.../Shapes/**`, `Lasso/**` | ink-tools |
| `App/Features/Elements/**` (text boxes, images, stickers, saved elements UI, study tape), `Packages/.../Stickers/**`, `Tape/**` | elements |
| `App/Features/Search/**` (search UI, OCR indexer, bookmarks, outline, links), `Packages/.../Search/**`, `Outline/**` | search |
| `App/Features/Present/**` (laser, presentation mode, external display scene, zoom window), `Packages/.../Present/**` | present |
| `App/Features/AudioStudy/**` (recording, playback, flashcards, review), `Packages/.../Study/**`, `Audio/**` | audio-study |
| `App/Features/DocTypes/**` (whiteboard, text document, app lock), `Packages/.../Documents/**`, `Lock/**` | doc-types |
| `AppTests/<Unit>/**`, `AppUITests/<Unit>UITests.swift` | that unit |
| `docs/superpowers/plans/**`, `docs/superpowers/specs/**` | foundation (plan author) |

Foundation creates these **stub files in other units' folders** (empty `register`, owned by that unit afterwards): `App/Features/{Editor/EditorFeature, Sync/SyncFeature, PdfIO/PdfIOFeature, InkTools/InkToolsFeature, Elements/ElementsFeature, Search/SearchFeature, Present/PresentFeature, AudioStudy/AudioStudyFeature, DocTypes/DocTypesFeature}.swift` and `App/Features/Present/PresentationSceneDelegate.swift`. Each unit also gets a `.gitkeep`-free placeholder so xcodegen sees the folder.

Integrators: resolve merge conflicts only; if two units truly collide on a path, the owner in this table wins.

## 3. Cross-unit interfaces

All in `App/Interfaces/` (foundation) unless noted. Signatures are exact; foundation may add `public`/`Sendable` details but must not rename or remove anything. App code is a single module so `public` is unnecessary. `@MainActor` everywhere UI-facing.

### 3.1 Feature modules and host

```swift
@MainActor protocol FeatureModule {
    static var id: String { get }
    static func register(into host: FeatureHost)
}

@MainActor final class FeatureHost {
    let services: AppServices
    let tools: ToolRegistry
    let layers: PageLayerRegistry
    let elementRenderers: ElementRendererRegistry
    let selectionActions: SelectionActionRegistry
    let documents: DocumentRouter
    let library: LibraryMenuRegistry
    let notebookMenu: NotebookMenuRegistry
    let settings: SettingsRegistry
    let touchObservers: InkTouchObserverRegistry
}

// App/Shell/FeatureModules.swift (foundation, final): names all modules
enum FeatureModules {
    static let all: [any FeatureModule.Type] = [
        EditorFeature.self, SyncFeature.self, PdfIOFeature.self, InkToolsFeature.self,
        ElementsFeature.self, SearchFeature.self, PresentFeature.self,
        AudioStudyFeature.self, DocTypesFeature.self,
    ]
}

@MainActor final class AppServices {
    let container: ModelContainer              // local SwiftData store
    let library: LibraryStore                  // folders/notebooks/pages CRUD, soft delete, restore, purge
    let pages: PageStore                       // ink data + elements persistence
    let revisions: RevisionStore               // Recovered area (PageRevision)
    let elementLibrary: any ElementLibrary
    let recognizer: any HandwritingRecognizing
    let settings: AppSettingsStore             // synced AppSetting + local UserDefaults
    var pageRenderer: any PageRenderer         // placeholder until Editor registers the real one
    var syncStatus: SyncStatusModel            // observable; Sync updates, Settings shows
}
```

### 3.2 Tool registry (toolbar tool + options row + canvas overlay)

```swift
struct ToolID: Hashable, Sendable, ExpressibleByStringLiteral, RawRepresentable {
    let rawValue: String
    init(rawValue: String)
    init(stringLiteral value: String)
    static let pen: ToolID = "pen", highlighter: ToolID = "highlighter", eraser: ToolID = "eraser",
               lasso: ToolID = "lasso", shapes: ToolID = "shapes", element: ToolID = "element",
               text: ToolID = "text", laser: ToolID = "laser", tape: ToolID = "tape",
               zoomWindow: ToolID = "zoomWindow"
}

enum ToolPlacement: Sendable { case primary(order: Int), more(order: Int) }   // primary row vs "more" menu

enum ToolInputPolicy: Sendable {
    case canvasHandlesInput          // PencilKit canvas gets touches; tool only configures it
    case overlayCapturesPencil       // overlay gets Pencil touches, fingers scroll/zoom
    case overlayCapturesAll          // overlay gets every touch (lasso with finger, text, laser)
}

@MainActor protocol EditorTool: AnyObject {
    var id: ToolID { get }
    var title: LocalizedStringResource { get }        // also the VoiceOver label
    var symbolName: String { get }                    // SF Symbol
    var placement: ToolPlacement { get }
    var supportedKinds: Set<NotebookKind> { get }     // e.g. all, or [.paged, .whiteboard]
    var inputPolicy: ToolInputPolicy { get }
    func activate(in editor: EditorContext)
    func deactivate(in editor: EditorContext)
    /// The slim second row under the tool row (presets, options). Return EmptyView-wrapped AnyView if none.
    func makeOptionsView(in editor: EditorContext) -> AnyView
    /// Transient overlay drawn above the page (lasso path, laser trail, shape preview). Page coordinate space, origin top-left, points.
    func makeOverlay(for page: PageContext, in editor: EditorContext) -> AnyView?
    /// Pencil double-tap / squeeze: return true if the tool consumed the event.
    func handlePencilAction(_ action: PencilAction, in editor: EditorContext) -> Bool
}
extension EditorTool { /* defaults: handlePencilAction false, makeOverlay nil */ }

enum PencilAction: Sendable { case doubleTap, squeeze }

@MainActor final class ToolRegistry {
    func register(_ tool: any EditorTool)                       // duplicate id traps in debug, last wins in release
    func tools(for kind: NotebookKind) -> [any EditorTool]      // sorted by placement order
    func tool(_ id: ToolID) -> (any EditorTool)?
}

@MainActor @Observable final class ToolState {
    var activeToolID: ToolID
    var previousToolID: ToolID                  // used by "switch back after erasing" and Pencil double-tap
    var inputMode: InputMode                    // .pencilOnly | .anyInput  (draw with finger or Pencil only)
    func select(_ id: ToolID)
}
enum InputMode: String, Sendable { case pencilOnly, anyInput }

struct ToolPreset: Codable, Hashable, Sendable, Identifiable {
    var id: UUID; var colorHex: String; var width: Double; var inkKind: InkKind?   // nil for non-ink tools
}
enum InkKind: String, Codable, CaseIterable, Sendable { case pen, fountainPen, monoline, pencil, crayon, watercolor, marker }
@MainActor protocol ToolPresetStore {
    func presets(for tool: ToolID) -> [ToolPreset]
    func setPresets(_ presets: [ToolPreset], for tool: ToolID)       // persisted via AppSettingsStore (synced key "toolPresets.<id>")
    func selectedPresetID(for tool: ToolID) -> UUID?
    func selectPreset(_ id: UUID, for tool: ToolID)
}
```

Editor implements `EditorContext` (3.3) and the default tools `pen`, `highlighter`, `eraser`. Everyone else only registers tools.

### 3.3 Editor context, page context, ink and element access

```swift
@MainActor protocol EditorContext: AnyObject {
    var notebook: Notebook { get }
    var services: AppServices { get }
    var toolState: ToolState { get }
    var presets: any ToolPresetStore { get }
    var selection: SelectionModel { get }
    var currentPage: (any PageContext)? { get }
    var visiblePages: [any PageContext] { get }
    var undoManager: UndoManager { get }                  // one per notebook; undo/redo covers ink, elements, page ops
    func goToPage(id: UUID, animated: Bool)
    func present(_ sheet: EditorSheet)                    // system sheet/popover host
    func showToast(_ message: LocalizedStringResource)
    func setZoomScale(_ scale: CGFloat, animated: Bool)
}
struct EditorSheet: Identifiable { let id = UUID(); let content: () -> AnyView; var detents: Set<PresentationDetent> }

@MainActor protocol PageContext: AnyObject {
    var notebookID: UUID { get }
    var pageID: UUID { get }
    var pageSize: CGSize { get }                          // points (pageSizing .infinite => current canvas size)
    var zoomScale: CGFloat { get }
    var ink: any PageInkAccess { get }
    var elements: any PageElementStore { get }
    var undoManager: UndoManager { get }
    func pageToScreen(_ rect: CGRect) -> CGRect           // for popovers/menus
    func screenToPage(_ point: CGPoint) -> CGPoint
}

@MainActor protocol PageInkAccess: AnyObject {
    var strokes: [IdentifiedStroke] { get }               // IdentifiedStroke { id: StrokeID; stroke: PKStroke }
    /// One undoable edit; ids are recomputed (StrokeIdentity) afterwards, the page is marked dirty and saved.
    func edit(_ name: LocalizedStringResource, _ body: (inout [PKStroke]) -> Void)
    func strokes(intersecting polygon: [CGPoint]) -> [IdentifiedStroke]      // lasso helper, page coords
    func render(strokeIDs: Set<StrokeID>, scale: CGFloat) -> UIImage?          // selection screenshot, flashcards
    var lastInkTouchDate: Date? { get }
}

@MainActor protocol PageElementStore: AnyObject {
    var all: [ElementValue] { get }                       // value copies, z-ordered
    @discardableResult func add(_ element: ElementValue, undoName: LocalizedStringResource) throws -> ElementValue
    func update(id: UUID, undoName: LocalizedStringResource, _ mutate: (inout ElementValue) -> Void) throws
    func remove(ids: Set<UUID>, undoName: LocalizedStringResource) throws          // soft delete
}

// Core (foundation): value type used everywhere instead of the @Model class
struct ElementValue: Codable, Hashable, Sendable, Identifiable {
    var id: UUID; var pageID: UUID; var kind: ElementKind
    var frame: CGRect; var rotation: Double; var zIndex: Int
    var payload: Data                 // JSON of the kind's payload struct (3.5)
    var assetID: UUID?
}
enum ElementKind: String, Codable, CaseIterable, Sendable { case text, image, sticker, tape, link, shape }
```

`UIImage`, `PKStroke` appear in App-only protocols; they do not enter Core.

### 3.4 Page layer stack, background provider, element renderers, page renderer

Bottom to top (spec): paper color, template, background (PDF), below-ink elements (images, stickers, text boxes), ink, above-ink elements (tape, shapes), transient overlays.

```swift
enum PageLayerSlot: Int, Comparable, Sendable {
    case paper = 0, template = 100, background = 200, belowInk = 300, ink = 400, aboveInk = 500, overlay = 600
}

struct PageSnapshot: Sendable {           // value copy of what a layer needs; safe across actors
    let pageID: UUID; let notebookID: UUID; let size: CGSize
    let backgroundAssetID: UUID?; let backgroundPageIndex: Int?
    let template: TemplateSpec; let paperColor: PaperColor
}

struct RenderOptions: Sendable {
    var includeBackground: Bool       // PDF background + template (export "with/without page backgrounds")
    var includeInk: Bool; var includeElements: Bool
    var forExport: Bool               // vector where possible
    var hideTape: Bool                // study tape hidden/shown state at render time
}

@MainActor protocol PageLayerProvider: AnyObject {
    var slot: PageLayerSlot { get }
    var order: Int { get }                                         // tie-break inside a slot
    func isActive(for page: PageSnapshot) -> Bool
    func makeLayerView(for page: PageContext) -> UIView            // live layer, added to the page's container
    func draw(page: PageSnapshot, into ctx: CGContext, rect: CGRect, options: RenderOptions) async throws   // export/thumbnail path
}

@MainActor final class PageLayerRegistry {
    func register(_ provider: any PageLayerProvider)
    func providers(for page: PageSnapshot) -> [any PageLayerProvider]      // sorted by slot, order
}
```
Editor registers paper, template (draws `TemplateSpec` vectors), ink, and the generic **element layer** (host for `belowInk` / `aboveInk`). **pdf-io registers the `.background` provider** for pages with `backgroundAssetID != nil` (PDFKit, tiled draw, cached). Search/links register nothing here (links use an element renderer).

```swift
@MainActor protocol ElementRenderer: AnyObject {
    var kind: ElementKind { get }
    var slot: PageLayerSlot { get }                                // .belowInk or .aboveInk
    func makeView(for element: ElementValue, page: PageContext) -> AnyView          // live, interactive (study tape tap, link tap)
    func draw(_ element: ElementValue, into ctx: CGContext, assets: AssetResolver, options: RenderOptions) async throws
    func hitTester(for element: ElementValue) -> any ElementHitTesting
    func beginEditing(_ element: ElementValue, page: PageContext, editor: EditorContext)   // double-tap on element
}
@MainActor final class ElementRendererRegistry {
    func register(_ renderer: any ElementRenderer)
    func renderer(for kind: ElementKind) -> (any ElementRenderer)?
}
protocol AssetResolver: Sendable { func data(for assetID: UUID) async throws -> Data }   // PageStore implements

// Core/Geometry (foundation): used by the lasso and by every renderer
protocol ElementHitTesting: Sendable {
    var bounds: CGRect { get }                                     // axis-aligned, page coords, includes rotation
    func intersects(polygon: [CGPoint]) -> Bool                    // lasso freeform path
    func contains(point: CGPoint) -> Bool                          // tap select
    func transformed(by t: CGAffineTransform) -> ElementValue      // returns the moved/scaled/rotated element
}
struct OrientedBoxHitTester: ElementHitTesting { init(element: ElementValue) }   // default for rect-like elements (SAT test)
```
Mapping of renderers: text, image, sticker, tape -> elements unit; shape -> ink-tools; link -> search. Until a unit lands, the editor draws an "unsupported element" placeholder (never deletes it).

```swift
@MainActor protocol PageRenderer: AnyObject {              // implemented by Editor (EditorPageRenderer), used by pdf-io, search, ink-tools, audio-study
    func renderImage(pageID: UUID, rect: CGRect?, scale: CGFloat, options: RenderOptions) async throws -> CGImage
    func renderPDFPage(pageID: UUID, into ctx: CGContext, mediaBox: CGRect, options: RenderOptions) async throws
    func thumbnail(pageID: UUID, width: CGFloat) async -> CGImage?       // cached on disk, invalidated by Page.inkHash
}
```

### 3.5 Selection model and actions

```swift
struct StrokeID: Hashable, Codable, Sendable { let rawValue: String }     // Core/Ink

@MainActor @Observable final class SelectionModel {
    private(set) var pageID: UUID?
    private(set) var strokeIDs: Set<StrokeID> = []
    private(set) var elementIDs: Set<UUID> = []
    private(set) var bounds: CGRect?                       // page coords
    var livePreviewTransform: CGAffineTransform = .identity // drag/resize/rotate in progress
    var isEmpty: Bool { get }
    func select(pageID: UUID, strokeIDs: Set<StrokeID>, elementIDs: Set<UUID>, bounds: CGRect)
    func clear()
}

@MainActor protocol SelectionTransforming: AnyObject {      // Editor implements; one undo step per gesture
    func apply(_ transform: CGAffineTransform, to selection: SelectionModel, in page: any PageContext) throws
    func delete(selection: SelectionModel, in page: any PageContext) throws
    func duplicate(selection: SelectionModel, in page: any PageContext, offset: CGSize) throws -> SelectionSnapshot
    func recolor(selection: SelectionModel, to colorHex: String, in page: any PageContext) throws
    func setWidth(selection: SelectionModel, to width: Double, in page: any PageContext) throws
}
struct SelectionSnapshot: Sendable { var strokes: Data /* PKDrawing data */; var elements: [ElementValue]; var bounds: CGRect }
// obtained via: editor.selectionTransformer (add `var selectionTransformer: any SelectionTransforming { get }` to EditorContext)

@MainActor protocol SelectionAction: AnyObject {
    var id: String { get }; var title: LocalizedStringResource { get }; var symbolName: String { get }
    var order: Int { get }
    func isEnabled(for selection: SelectionModel, editor: EditorContext) -> Bool
    func perform(selection: SelectionModel, page: any PageContext, editor: EditorContext) async throws
}
@MainActor final class SelectionActionRegistry { func register(_ action: any SelectionAction); var actions: [any SelectionAction] { get } }
```
The selection overlay (handles, floating action menu built from `SelectionActionRegistry.actions`) is owned by **editor**; the lasso gesture that *creates* a selection is owned by ink-tools. Elements tools select a single element by setting the same model. Built-in actions are registered by the owner of the feature: ink-tools (copy, cut, paste, duplicate, delete, recolor, width, screenshot, convert to text), elements ("Save as element"), search ("Link to..."), audio-study ("Make flashcard").

Payload structs (Core/Elements/Payloads, foundation, all `Codable` with `version: Int = 1`): `TextPayload`, `ImagePayload` (crop rect, original size), `StickerPayload` (stickerID, tint), `TapePayload` (colorHex, isRevealed, style), `LinkPayload` (target: `.page(UUID)`, `.notebook(UUID)`, `.url(URL)`; region label), `ShapePayload` (shapeKind, points, strokeHex, fillHex?, lineWidth).

### 3.6 Saved elements

```swift
@MainActor protocol ElementLibrary: AnyObject {            // implementation: foundation (App/Shell/ElementLibraryStore.swift)
    func all() throws -> [SavedElementValue]
    @discardableResult func save(name: String, category: String, from snapshot: SelectionSnapshot, thumbnail: Data) throws -> SavedElementValue
    func rename(id: UUID, to name: String) throws
    func delete(id: UUID) throws                           // soft delete, synced
    func insert(_ saved: SavedElementValue, into page: any PageContext, at center: CGPoint, scale: CGFloat) throws -> SelectionSnapshot
}
struct SavedElementValue: Identifiable, Sendable { var id: UUID; var name: String; var category: String; var size: CGSize; var thumbnail: Data }
```
Used by ink-tools (lasso paste of a saved element) and elements (library browser, "Save as element" action, sticker catalog insert).

### 3.7 Document-kind router

```swift
enum NotebookKind: String, Codable, CaseIterable, Sendable { case paged, whiteboard, text }

@MainActor protocol DocumentEditorFactory {
    var kind: NotebookKind { get }
    func makeEditor(for notebook: Notebook, host: FeatureHost) -> AnyView
}
@MainActor final class DocumentRouter {
    func register(_ factory: any DocumentEditorFactory)
    func editor(for notebook: Notebook, host: FeatureHost) -> AnyView   // placeholder "Coming soon" view if unregistered; never crashes
}

enum PageSizing: Sendable { case fixed(CGSize), infinite(initial: CGSize) }   // whiteboard = infinite
// Editor exposes the reusable pieces doc-types needs (App/Features/Editor, public inside module):
//   EditorScaffold(notebook:host:sizing:)      top bar + tool row + options row + canvas host for a PageSizing
//   Editor registers .paged; doc-types registers .whiteboard (EditorScaffold with .infinite) and .text (own editor, no tool row)
```

### 3.8 Library menu extension points

```swift
struct LibraryNewItem: Identifiable {
    let id: String; let title: LocalizedStringResource; let symbolName: String; let order: Int
    let action: @MainActor (LibraryActionContext) -> Void
}
struct LibraryImportHandler {
    let id: String; let contentTypes: [UTType]
    let handle: @MainActor ([URL], LibraryActionContext) async throws -> Void   // security-scoped URLs
}
struct NotebookContextAction: Identifiable {          // cover context menu & multi-select actions
    let id: String; let title: LocalizedStringResource; let symbolName: String; let order: Int; let isDestructive: Bool
    let perform: @MainActor ([Notebook], LibraryActionContext) async throws -> Void
}
@MainActor struct LibraryActionContext {
    let services: AppServices; let currentFolderID: UUID?
    let present: (AnyView) -> Void; let open: (Notebook) -> Void; let showError: (LocalizedError) -> Void
}
@MainActor final class LibraryMenuRegistry {
    func registerNewItem(_ item: LibraryNewItem)             // foundation registers: Notebook, Folder; doc-types: Whiteboard, Text document
    func registerImportItem(_ handler: LibraryImportHandler) // pdf-io: PDF, Images; pdf-io: .sheafnote backup
    func registerNotebookAction(_ action: NotebookContextAction)   // pdf-io: Export
    func registerSearchDestination(_ make: @escaping @MainActor (LibraryActionContext) -> AnyView)   // search: sidebar "Search"
    func registerBackgroundTask(id: String, _ run: @escaping @MainActor (AppServices) async -> Void)  // run on launch/foreground (search OCR, auto backup)
}
```
Foundation's library already shows: New menu (items from registry plus Notebook/Folder), Import entry (handlers from registry, opens `.fileImporter` with the union of types, also drop and "Open in" via `onOpenURL` routed to the handler whose types match), cover context menu rename/change cover/duplicate/move/favorite/delete plus registered actions, multi-select bar.

### 3.9 Notebook-level menu extension points (editor chrome)

```swift
enum EditorBarSlot: Sendable { case leading(order: Int), trailing(order: Int) }   // beside back/thumbnails (leading) or undo/redo (trailing)
struct EditorBarItem: Identifiable {
    let id: String; let slot: EditorBarSlot; let kinds: Set<NotebookKind>
    let makeView: @MainActor (EditorContext) -> AnyView         // a Button/Menu with label+accessibility already set
}
enum NotebookMenuGroup: Int, Sendable { case share, view, insert, tools }       // groups inside the "more" menu, in this order
struct NotebookMenuItem: Identifiable {
    let id: String; let group: NotebookMenuGroup; let order: Int; let kinds: Set<NotebookKind>
    let title: LocalizedStringResource; let symbolName: String
    let isEnabled: @MainActor (EditorContext) -> Bool
    let perform: @MainActor (EditorContext) -> Void
}
struct PageMenuItem: Identifiable {                             // thumbnail grid context menu and multi-select toolbar
    let id: String; let order: Int; let title: LocalizedStringResource; let symbolName: String
    let perform: @MainActor ([UUID] /*page ids*/, EditorContext) async throws -> Void
}
struct NavigatorTab: Identifiable {                             // tabs in the page navigator sheet; editor owns "Pages"
    let id: String; let order: Int; let title: LocalizedStringResource; let symbolName: String
    let makeView: @MainActor (EditorContext) -> AnyView
}
@MainActor final class NotebookMenuRegistry {
    func registerBarItem(_ item: EditorBarItem)
    func registerMenuItem(_ item: NotebookMenuItem)
    func registerPageMenuItem(_ item: PageMenuItem)
    func registerNavigatorTab(_ tab: NavigatorTab)
}
```
Who registers: pdf-io: bar item "Share/Export" (`leading`), page menu "Export pages", menu "Insert PDF pages" (insert); search: bar items "Search in notebook" and "Bookmark" (`leading`), navigator tabs "Bookmarks" and "Outline", menu "Add outline entry"; present: menu "Present" (view); audio-study: menu "Record audio" (tools) plus a playback bar item (`trailing`), page menu "Make flashcards"; editor: add page, page template, scroll direction, page navigator. Tool-specific entries (tape "hide all / show all", zoom window) live in the tool's options row.

### 3.10 Settings sections

```swift
struct SettingsSection: Identifiable {
    let id: String; let order: Int; let title: LocalizedStringResource; let symbolName: String
    let makeView: @MainActor (AppServices) -> AnyView            // a Form section content or pushed screen
}
@MainActor final class SettingsRegistry { func register(_ section: SettingsSection); var sections: [SettingsSection] { get } }
```
Order values: General 0 (foundation), Pencil & gestures 10 (editor), iCloud sync 20 (sync), Import & backup 30 (pdf-io), Search 40 (search), App lock 50 (doc-types), Audio 60 (audio-study), About 100 (foundation).

### 3.11 Ink touch observers (draw-and-hold, straight highlighter)

PencilKit does not expose a stroke in progress. Editor's canvas host adds a non-cancelling, non-delaying `UIGestureRecognizer` that forwards raw touches:

```swift
struct InkSample: Sendable { var location: CGPoint /* page coords */; var timestamp: TimeInterval; var force: CGFloat; var altitude: CGFloat; var azimuth: CGFloat; var isPencil: Bool }
@MainActor protocol InkTouchObserver: AnyObject {
    var activeToolIDs: Set<ToolID> { get }                          // only called while one of these is the active tool
    func strokeBegan(_ s: InkSample, page: any PageContext, editor: EditorContext)
    func strokeMoved(_ samples: [InkSample], page: any PageContext, editor: EditorContext)   // coalesced + predicted removed
    func strokeEnded(_ s: InkSample, page: any PageContext, editor: EditorContext)
    func strokeCancelled(page: any PageContext, editor: EditorContext)
}
@MainActor final class InkTouchObserverRegistry { func register(_ o: any InkTouchObserver) }
```
Draw-and-hold (ink-tools): observer tracks samples; when movement stays under 2 pt for 0.6 s while the Pencil is down, it asks `ShapeRecognizer` (Core) and, if recognized, edits the just-finished PKStroke after `strokeEnded` through `page.ink.edit` (replace last stroke by the snapped one). Straight highlighter line: same mechanism with a line fit when the highlighter option is on.

### 3.12 Handwriting recognition (Core/Recognition, foundation)

```swift
struct RecognizedLine: Sendable, Hashable { var text: String; var confidence: Float; var boundingBox: CGRect /* normalized, bottom-left origin as Vision */ }
struct RecognizedText: Sendable, Hashable { var lines: [RecognizedLine]; var fullText: String { get } }
protocol HandwritingRecognizing: Sendable {
    func recognizeText(in image: CGImage, languages: [String]) async throws -> RecognizedText   // [] = automatic, English first
}
struct VisionHandwritingRecognizer: HandwritingRecognizing {}   // VNRecognizeTextRequest, .accurate, on-device only
enum RecognitionError: LocalizedError { case cancelled, visionFailed(String) }
```
Users: search (page OCR), ink-tools (lasso "convert to text"). Tests render text into a CGImage with CoreText on the Mac and assert the recognized words.

### 3.13 Stores (Core/Store, foundation) used across units

```swift
@MainActor final class LibraryStore {   // folders/notebooks CRUD; every mutation calls markDirty
    func createNotebook(title: String, kind: NotebookKind, cover: CoverSpec, template: TemplateSpec, paperSize: PaperSize, orientation: PageOrientation, paperColor: PaperColor, in folder: UUID?) throws -> Notebook
    func createFolder(name: String, in parent: UUID?) throws -> Folder
    func softDelete(_ items: [LibraryItemRef]) throws        // sets deletedAt, never removes data
    func restore(_ items: [LibraryItemRef]) throws
    func purgeExpired(now: Date) throws -> Int               // only items with deletedAt older than 30 days
    func duplicate(_ notebook: Notebook) throws -> Notebook
    func move(_ items: [LibraryItemRef], to folder: UUID?) throws
}
@MainActor final class PageStore: AssetResolver {
    func addPage(to notebookID: UUID, at position: PagePosition, template: TemplateSpec?) throws -> Page   // .before(UUID) | .after(UUID) | .end
    func duplicate(pageID: UUID) throws -> Page
    func softDelete(pageIDs: [UUID]) throws                  // also snapshots into RevisionStore first
    func move(pageID: UUID, between previous: UUID?, and next: UUID?) throws   // fractional SortKey
    func saveInk(pageID: UUID, drawingData: Data, strokeIDs: [StrokeID]) throws   // sets inkHash, modifiedAt, syncDirty
    func inkData(pageID: UUID) -> Data?
    func importAsset(data: Data, kind: AssetKind, filename: String?) throws -> Asset    // dedup by sha256
}
@MainActor final class RevisionStore {  // Recovered area, local only
    func snapshot(page: Page, reason: RevisionReason) throws -> PageRevision      // reasons: conflict, beforeDelete, beforeClear, restore
    func revisions(for pageID: UUID) -> [PageRevision]
    func restore(_ revision: PageRevision) throws -> Page          // restores as a NEW page after the original; never overwrites
    func purgeExpired(now: Date) throws -> Int                     // > 30 days
}
extension Notification.Name { static let sheafnoteModelDidChange: Self }   // posted by markDirty(); Sync listens
```
Rule for all units: **no code path may remove ink or a notebook except `softDelete` (reversible for 30 days) or an explicit user "Delete permanently / Empty" action behind a destructive confirmation.** Clearing a page, deleting pages, replacing a PDF background and conflict resolution all call `RevisionStore.snapshot` first.

## 4. Data model, CloudKit mapping, merge

### 4.1 SwiftData schema (foundation, `Packages/SheafnoteCore/Sources/SheafnoteCore/Models`, complete for all phases)

`enum SheafnoteSchemaV1: VersionedSchema` listing all models; `SheafnoteMigrationPlan` with no stages yet. Store lives in Application Support (`Sheafnote.store`), NOT CloudKit-backed (`cloudKitDatabase: .none`). Large `Data` uses `@Attribute(.externalStorage)`.

Every synced model conforms to `SyncableRecord` and has these stored properties (`@Attribute(.unique) var id: UUID` first):

```swift
protocol SyncableRecord: PersistentModel {
    var id: UUID { get }
    var createdAt: Date { get }
    var modifiedAt: Date { get set }        // set by markDirty
    var deletedAt: Date? { get set }        // soft delete (tombstone); purge >30 days later removes the row and the CK record
    var syncDirty: Bool { get set }         // true until the record is confirmed sent
    var dirtyFields: [String] { get set }   // property names changed since last send (field-level conflict merge)
    var ckSystemFields: Data? { get set }   // CKRecord.encodeSystemFields archive of last known server record
    var formatVersion: Int { get }          // currently 1
    static var recordType: String { get }   // CloudKit record type name (4.2)
}
func markDirty<T: SyncableRecord>(_ r: T, fields: [String])   // sets modifiedAt = .now, syncDirty = true, unions dirtyFields, posts notification
```

Models (only domain properties listed; sync properties above are on all unless noted):

| Model | Properties |
|---|---|
| `Folder` | name, parentID: UUID?, sortKey: String, isFavorite: Bool, colorName: String? |
| `Notebook` | title, kind: NotebookKind(raw String), folderID: UUID?, coverSpec: Data (CoverSpec JSON), defaultTemplate: Data (TemplateSpec JSON), paperSize: String, orientation: String, paperColor: String, scrollDirection: String (`vertical`/`horizontal`), isFavorite, isLocked: Bool, lastOpenedAt: Date?, sortKey: String, richText: Data? (text documents, `RichTextDocument` JSON, asset), pdfOutlineImported: Bool |
| `Page` | notebookID, sortKey: String, widthPts: Double, heightPts: Double, templateOverride: Data? (TemplateSpec), paperColorOverride: String?, backgroundAssetID: UUID?, backgroundPageIndex: Int?, inkData: Data? (PKDrawing representation, external, asset), strokeIDs: [String] (ordered, same order as `inkData` strokes), inkHash: String, baseInkData: Data? (LOCAL ONLY, last server version), baseStrokeIDs: [String] (LOCAL ONLY), recognizedText: String, ocrInkHash: String (hash OCR ran on), isInfinite: Bool |
| `PageElement` | pageID, kind: ElementKind, x, y, width, height, rotation: Double, zIndex: Int, payload: Data (JSON, versioned), assetID: UUID? |
| `Asset` | kind: AssetKind (`pdf`,`image`,`audio`,`thumbnail`), data: Data (external, asset), byteCount: Int, sha256: String, filename: String?, uti: String? |
| `OutlineEntry` | notebookID, title, pageID: UUID?, pdfPageIndex: Int?, parentID: UUID?, sortKey, source: `user`/`pdf` |
| `Bookmark` | notebookID, pageID, title: String? |
| `AudioRecording` | notebookID, assetID, title, startedAt: Date, duration: Double, timeline: Data (JSON `[AudioStrokeMark]`: pageID, strokeID, offset seconds) |
| `Flashcard` | notebookID, deck: String, sourcePageID: UUID?, frontImage: Data (PNG, asset), backImage: Data (PNG, asset), frontText: String?, backText: String? |
| `StudyState` | flashcardID, ease: Double (2.5 start), intervalDays: Int, repetitions: Int, lapses: Int, dueAt: Date, lastReviewedAt: Date? |
| `SavedElement` | name, category, width, height, inkData: Data? (PKDrawing, asset), elements: Data (JSON `[ElementValue]`), thumbnail: Data |
| `AppSetting` | key: String (unique with id), valueJSON: Data (synced settings: tool presets, last-used template, scroll defaults) |
| `PageRevision` | LOCAL ONLY, not Syncable: id, pageID, notebookID, reason, createdAt, expiresAt, inkData, strokeIDs, elements: Data, note: String? |

Fractional `sortKey`: `Core/Ordering/SortKey.swift`, base-62 strings, `SortKey.between(_ a: String?, _ b: String?) -> String`; collisions between devices are broken by `id`. Tests: monotonic, 10 000 inserts at the same spot stay bounded, concurrent equal keys sort deterministically.

### 4.2 CloudKit record mapping (sync owns the code in `Packages/.../Sync/RecordMapper.swift`)

- Database: private. One custom zone `SheafnoteZone` (`CKRecordZone.ID(zoneName: "SheafnoteZone", ownerName: CKCurrentUserDefaultName)`). Record name = `id.uuidString`. Container `iCloud.co.xanom.sheafnote`.
- Record types (prefix `SN`): `SNFolder`, `SNNotebook`, `SNPage`, `SNPageElement`, `SNAsset`, `SNOutlineEntry`, `SNBookmark`, `SNAudioRecording`, `SNFlashcard`, `SNStudyState`, `SNSavedElement`, `SNSetting`. `PageRevision` and all LOCAL ONLY properties never leave the device.
- Rule: CloudKit field name = Swift property name. `String`/`Date`/`Bool` map directly; `Int`/`Double` -> `Int64`/`Double`; `UUID` -> `String`; enums -> raw `String`; `[String]` -> list of String; small `Data`/JSON (< 100 KB) -> `Bytes`; fields marked "asset" above -> `CKAsset` (written to a temp file under Caches, deleted after send). Common fields on every record: `formatVersion: Int64`, `createdAt`, `modifiedAt`, `deletedAt` (nil = alive). Relationships are plain String UUID fields (`notebookID`, `pageID`, `folderID`, `parentID`, `assetID`), NOT `CKRecord.Reference`, because CKSyncEngine sends batches unordered and our deletes are soft; the receiver tolerates a child arriving before its parent (parent-less rows are kept and shown once the parent arrives; never dropped).
- Asset fields: `SNPage.inkData`, `SNAsset.data`, `SNNotebook.richText`, `SNFlashcard.frontImage`/`backImage`, `SNSavedElement.inkData`/`thumbnail` when > 100 KB, otherwise inline.
- Forward compatibility: unknown fields are ignored on read; unknown `formatVersion` greater than ours: keep the row, mark `readOnlyFromNewerVersion`, do not upload edits over it, show "Update Sheafnote to edit" in the UI. Schema only grows (no rename/remove/type change); deploy the schema to Production before TestFlight/App Store (note in README, a human step).
- Sync state: `CKSyncEngine.State.Serialization` saved to `Application Support/SheafnoteSync/state.json` (atomic write). `ckSystemFields` on each row lets us rebuild the `CKRecord` for sends.
- Triggers: `.sheafnoteModelDidChange` -> debounce 1 s -> add `pendingRecordZoneChanges` for rows with `syncDirty`. Push via `CKSyncEngine` automatic scheduling; foreground fetch on scene active.
- Account events: `signIn` -> create zone, mark everything dirty, upload. `signOut` -> engine off, local data untouched, `syncStatus = .signedOut`. `switchAccounts` -> local data untouched; engine reset; ask the user via a sheet: "Upload this device's notebooks to the new iCloud account?" (default Yes); nothing is deleted either way. Settings toggle "iCloud sync" (local-only mode = engine not started).
- Errors map to `SyncStatusModel` states (`idle`, `syncing`, `offline`, `signedOut`, `quotaExceeded`, `error(String)`) with user-friendly text; retries use CKSyncEngine's built-in backoff; no silent catch.

### 4.3 Conflict handling and stroke merge

Stable stroke identity (foundation, `Core/Ink/StrokeIdentity.swift`; PKStroke has no ID):

```swift
struct StrokeRecord: Codable, Hashable, Sendable {     // PencilKit-free snapshot, built in App by PKStroke+StrokeRecord.swift (editor)
    var inkType: String; var colorRGBA: [Double]       // 4 doubles
    var transform: [Double]                            // a,b,c,d,tx,ty
    var creationDate: Date; var maskPath: Data?
    var points: [StrokePoint]                          // x,y,timeOffset,force,azimuth,altitude,width,height (Float32)
}
enum StrokeIdentity { static func id(for s: StrokeRecord) -> StrokeID }   // SHA-256 over canonical little-endian bytes of ALL fields above, hex, first 32 chars
```
A transformed or recolored stroke therefore gets a NEW id (it is "delete old + add new"), which is exactly what three-way merge needs. Editor computes ids after each edit off the main thread and stores `Page.strokeIDs` with the ink; `strokeIDs` order equals `drawing.strokes` order.

Three-way merge (sync, `Core/Sync/StrokeMerger.swift`, pure and tested):

```swift
struct StrokeEntry: Hashable, Sendable { var id: StrokeID; var creationDate: Date }
enum MergeSide: Sendable { case ours, theirs }
struct MergeResult: Sendable { var ordered: [(id: StrokeID, from: MergeSide)]; var addedFromTheirs: Int; var removedByTheirs: Int }
enum StrokeMerger {
    /// base = Page.baseStrokeIDs (last server version we synced), ours = local now, theirs = server now.
    /// keep = (ours ∪ theirs) minus (base − ours) minus (base − theirs); sorted by creationDate then id.
    static func merge(base: [StrokeEntry], ours: [StrokeEntry], theirs: [StrokeEntry]) -> MergeResult
}
```
App side (`App/Features/Sync/PageInkMerger.swift`) rebuilds a `PKDrawing` from the chosen `PKStroke`s of each side. Page conflict flow on `serverRecordChanged` for `SNPage`:
1. If `base` is missing (never synced) or `inkHash` equal: take the field-level result only.
2. Else try `StrokeMerger`; write merged ink, `strokeIDs`, new `baseInkData = theirs`, mark dirty, send again.
3. If the server ink cannot be decoded or merge throws: keep OURS as the live page, store THEIRS as `PageRevision(reason: .conflict)` for 30 days (Recovered area, UI in Sync's settings screen with restore as new page). Always snapshot OURS-before-merge too. Never drop ink silently.
4. Non-ink fields (title, sortKey, template, background, flags): per field; if a field is in `dirtyFields` ours wins, else take the server's.
Other record types: same field-level rule; `deletedAt` set on either side wins over edits (delete is a tombstone), but a restore (`deletedAt = nil`) with a later `modifiedAt` than the delete wins. Elements: per-record last-writer-wins by `modifiedAt`, deletions as tombstones. Reorder uses fractional keys so two devices moving different pages never conflict.

## 5. Test strategy

General: write tests first for logic; Core target 80% line coverage (check with `--enable-code-coverage` and `xcrun llvm-cov report`), App unit tests (`SheafnoteTests`) for view models and PencilKit-dependent glue on the simulator, XCUITest for main flows. UI tests launch with `-UITestMode 1 -UITestScenario <name>` (foundation's `UITestSeed`: in-memory store, sync off, animations off, deterministic ids; scenarios `empty`, `libraryBasic`, `notebookWith3Pages`, `pdfNotebook`, `recorded`). In `docs`/README: do not use Playwright or live browser tooling; this is native.

| Unit | Core tests (swift test) | App tests / UI tests |
|---|---|---|
| foundation | models + migration plan opens V1 store, SortKey, SoftDelete/purge (30 d boundary), TemplateSpec rendering geometry (line positions for every paper type, planner layout), CoverSpec set (20 unique), StrokeIdentity (stable, sensitive to each field), OrientedBoxHitTester, VisionHandwritingRecognizer on rendered text, LibraryStore/PageStore/RevisionStore on in-memory container, ElementLibrary save/insert | library view models (sort, filter, multi-select), UITest `LibraryUITests`: create notebook through the sheet, folder, favorite, delete -> Recently Deleted -> restore |
| editor | n/a beyond geometry helpers | `PKStroke+StrokeRecord` round-trip, undo manager integration, ToolPresetStore, scroll/zoom model, SelectionTransformer on a PKDrawing; UITests `EditorUITests`: open notebook, write via synthesized drag on canvas, add page, reorder in navigator, undo/redo, switch tool |
| sync | RecordMapper round-trip for every model, StrokeMerger (add/add, delete/add, delete/delete, same stroke both sides, empty base, large 5 000 strokes under 200 ms), field-level conflict resolver, tombstone vs restore, `SyncCoordinator` against `InMemoryCloud` simulating two devices with offline edits, account sign-out/switch (no local deletion), unknown formatVersion | `PageInkMerger` with real PKDrawings, `SyncStatusModel` states; UITest: settings shows sync section and local-only toggle |
| pdf-io | PDF page mapping, outline extraction, export planner (page ranges, naming, with/without background), `.sheafnote` archive write/read round-trip, zip determinism, corrupt archive rejected with typed error, auto-backup naming/retention | 500-page PDF import time budget (generated PDF fixture, measured), UITest `PdfIOUITests`: import fixture PDF, export PDF and verify file exists and page count |
| ink-tools | ShapeRecognizer (line, arrow, rect, ellipse/circle, triangle, polygon, arc, rejects scribbles, tolerance of noisy input), snap geometry, lasso polygon vs stroke bbox/segments, selection bounds, straight-line fit, group transform math | lasso selects/moves strokes on PKDrawing; UITest `InkToolsUITests`: draw a square, lasso it, move, delete, undo |
| elements | sticker catalog integrity (unique ids, valid paths), tape state toggling, text payload codec, crop math | element renderers render non-empty CGImage; UITest `ElementsUITests`: add text box, add sticker, tape hide/show |
| search | tokenizer, ranking, snippet highlight ranges, index update/removal, bookmark ordering, outline tree build, link target codec, OCR scheduling policy (only when `inkHash != ocrInkHash`) | OCR indexer runs Vision on rendered handwriting fixture; UITest `SearchUITests`: search typed text and title, open result, bookmark a page, outline jump |
| present | laser trail fade model (time-based decay, max points), zoom window advance logic (margin, auto-advance distance), mirroring state machine | external-scene configuration unit test; UITest `PresentUITests`: laser tool selectable, zoom window appears (external display not testable; stated plainly) |
| audio-study | SM-2 scheduler (grades 0-5, interval table, lapse, due ordering, 10 000-card performance), timeline mapping (offset <-> stroke, seek), flashcard region math | recorder state machine with a fake `AVAudioRecorder` wrapper, playback seek on stroke tap; UITest `AudioStudyUITests`: create card from page, review it (record permission scripted via launch arg fake) |
| doc-types | RichTextDocument codec/operations (headings, lists, checklists toggle), whiteboard canvas expansion bounds, lock policy (grace period, per-notebook flags) | `LAContext` wrapper with fake; UITest `DocTypesUITests`: create whiteboard, draw, create text doc, type, checklist |

Quality gate for every unit: `scripts/verify.sh <label>` green, no compiler warnings introduced (Swift 6 strict concurrency on), VoiceOver labels on every control, Dynamic Type safe layouts (no fixed font sizes except in page content), strings in the unit's table, functions < 50 lines, files <= 400 lines (800 hard).

## 6. Work units, order and checklists

Order: **foundation** (main) -> **editor** and **sync** (parallel worktrees, merged to main) -> **pdf-io, ink-tools, elements, search, present, audio-study, doc-types** (7 parallel worktrees from merged main) -> integrators merge all `unit/*` branches -> reviewers and fixers.

### 6.1 foundation (sequential, on main)
- [ ] `project.yml`: targets `Sheafnote` (app, sources `App/`, includes `Info.plist` keys, entitlements, `PrivacyInfo.xcprivacy`), `SheafnoteTests` (`AppTests/`), `SheafnoteUITests` (`AppUITests/`), local package `SheafnoteCore`; Swift 6, iOS 26.0, team VTQW687WBQ, scheme `Sheafnote` with both test targets; `.gitignore` has `Sheafnote.xcodeproj`, `.derived/`.
- [ ] Info.plist for all units: `NSCameraUsageDescription`, `NSMicrophoneUsageDescription`, `NSPhotoLibraryAddUsageDescription`, `NSFaceIDUsageDescription`, `UIBackgroundModes: remote-notification`, `UIApplicationSupportsMultipleScenes`, scene manifest with `UIWindowSceneSessionRoleExternalDisplayNonInteractive` -> `PresentationSceneDelegate`, `CFBundleDocumentTypes` (PDF, images, `.sheafnote`), exported UTType `co.xanom.sheafnote.archive`, `LSSupportsOpeningDocumentsInPlace`. Entitlements: iCloud container + CloudKit, push (`aps-environment` development). Privacy manifest: no tracking, required-reason APIs actually used (UserDefaults, file timestamp, disk space).
- [ ] Core package skeleton, models + `SheafnoteSchemaV1`, `SyncableRecord`, `markDirty`, `SortKey`, `TemplateSpec` (blank, ruled narrow/college/wide, grid sizes, dotted, Cornell, music staff, planner daily/weekly/monthly/to-do) with vector drawing functions into `CGContext`, `PaperSize` (A4, Letter, A5, square), `PaperColor` (white, yellow, dark), orientation, `CoverSpec` + 20 own covers (solid colors + simple patterns) drawn in SwiftUI/CoreGraphics, `StrokeRecord`/`StrokeIdentity`, geometry + `OrientedBoxHitTester`, payload structs, `HandwritingRecognizing` + Vision implementation, `LibraryStore`/`PageStore`/`RevisionStore`/`AppSettingsStore`/`ElementLibraryStore`, 30-day purge job registered as a background task at launch.
- [ ] `App/Interfaces/**` exactly as section 3 with working registries; `AppServices`, `FeatureHost`, `FeatureModules`, unit stubs, `PresentationSceneDelegate` stub, `AppDelegate` scene routing.
- [ ] Library UI: `NavigationSplitView` (sidebar Documents, Favorites, Search, Recently Deleted, folder tree), cover grid + list toggle, folder tiles, sort name/created/modified, "+ New" menu from registry, Import entry, Select mode with multi-move/delete, cover context menus, Recently Deleted (restore, delete permanently with confirmation, "Empty" confirmation), iPhone `NavigationStack` two-column grid.
- [ ] New notebook sheet: title, cover carousel, paper carousel grouped by type, paper color, orientation, size; shared with "change page template later" via a reusable `TemplatePickerView` (editor uses it).
- [ ] App shell: root view opening notebooks through `DocumentRouter` (placeholder editor view showing page count until editor lands), settings scaffold with General (default paper, units) and About (version, license, "No tracking" statement), String Catalog setup, AccentColor and own app icon (generated by `scripts/make-icon.swift`, original artwork), `README.md`, MIT `LICENSE`, `docs/archive-format.md` placeholder.
- [ ] `scripts/verify.sh`, `AppUITests/Support`, `UITestSeed`, `LibraryUITests`.
- [ ] Commit in small conventional commits to main; tag `foundation-done` locally.

### 6.2 editor (worktree `unit/editor`)
- [ ] `EditorContext`/`PageContext` implementations, `NotebookSession` (one `UndoManager` per notebook), `EditorScaffold(notebook:host:sizing:)`, `PagedEditorFactory` registered with the router.
- [ ] Chrome: top bar left (back, page navigator, bar items), center tool row from `ToolRegistry`, right (undo, redo, more menu from `NotebookMenuRegistry` plus add page, page template, scroll direction); slim options row from `makeOptionsView`; Liquid Glass toolbars via system `.toolbar`/`glassEffect`; iPhone bottom toolbar; gray canvas with soft page shadow.
- [ ] Page canvas: `PKCanvasView` host (`UIViewRepresentable`) with `drawingPolicy` from `InputMode`, page container view stacking the layers from `PageLayerRegistry`, element layer host using `ElementRendererRegistry`, overlay host from active tool, `InkTouchObserver` gesture, pinch zoom, vertical continuous and horizontal paged scrolling (`Notebook.scrollDirection`, toggle in more menu), lazy page loading and tiled rendering, debounced ink save (1 s idle + on page change/background) through `PageStore.saveInk` with `StrokeIdentity` computed off-main.
- [ ] Tools: `PenTool` (all `InkKind`s: pen, fountainPen, monoline, pencil, crayon, watercolor; marker for highlighter), color + 3 width presets, "+" custom, tap active preset to edit, `HighlighterTool` (no straight line), `EraserTool` (whole-stroke, partial/pixel via PencilKit, sizes, "erase highlighter only", "switch back to previous tool after erasing").
- [ ] `ToolPresetStore` over `AppSettingsStore`; Apple Pencil double-tap and squeeze (`UIPencilInteraction`, setting: switch to eraser / previous tool / show palette); input mode setting (Pencil only / any input) in the "Pencil & gestures" settings section.
- [ ] Page ops: add (before/after/end), duplicate, delete (snapshot first), reorder by drag in the thumbnail grid, go to page, change page template (uses foundation `TemplatePickerView`, apply to this page / all pages); thumbnail grid navigator with `NavigatorTab` host.
- [ ] Undo/redo per notebook across ink, elements and page operations.
- [ ] Selection overlay (handles, floating menu from `SelectionActionRegistry`), `SelectionTransformer`.
- [ ] `EditorPageRenderer` (set into `services.pageRenderer`), registered layers paper/template/ink/element layer, thumbnail cache.
- [ ] Tabs (iPad, open notebooks across the top) and multi-window open ("Open in new window" via `UIApplication.requestSceneSessionActivation`, supports Stage Manager and Split View).
- [ ] `PKStroke+StrokeRecord.swift` adapter; "unsupported element" placeholder renderer.

### 6.3 sync (worktree `unit/sync`)
- [ ] Core: `RecordMapper` (all 12 record types, section 4.2), `ConflictResolver`, `StrokeMerger`, `PurgePolicy`, `SyncCoordinator` over `protocol CloudTransport` with `InMemoryCloud` test double (two devices), TDD in that order.
- [ ] App: `CKSyncEngineTransport` (`CKSyncEngine` delegate: pending changes, fetched changes applied in one background `ModelContext` transaction, sent results, conflicts, `zoneNotFound`, quota, account changes), `PageInkMerger`, `SyncController` (observes `.sheafnoteModelDidChange`, scene active), state persistence, `SyncStatusModel` updates.
- [ ] Settings section "iCloud sync": status, last sync time, local-only toggle, Recovered pages list with restore-as-new-page, "Sync now", sign-out/switch-account explanations and upload prompt.
- [ ] README section "Sync and CloudKit": zone/record schema, production-schema deploy step (human), how to test with two simulators or devices. Documented limitation: simulator CloudKit needs a signed-in iCloud account, so the automated sync tests use `InMemoryCloud`; real CloudKit verification is listed as not done by agents.

### 6.4 pdf-io (worktree `unit/pdf-io`)
- [ ] `PDFBackgroundLayer` provider (`.background` slot, PDFKit page draw, tiled + cached, vector at any zoom); `PdfImporter` (new notebook or insert pages into existing at a position, stores one `Asset(pdf)` per import, `backgroundAssetID` + `backgroundPageIndex` per page, page size from media box, imports the PDF outline into `OutlineEntry(source: .pdf)`), image import as pages (Photos, Files).
- [ ] Library registrations: Import items (PDF, images, `.sheafnote`), drop and share-sheet/open-in handling, notebook context action "Export...".
- [ ] Export: `ExportOptionsSheet` (whole notebook / selected pages / current page; PDF with or without page backgrounds; PNG/JPEG images), `PDFExporter` via `PageRenderer.renderPDFPage` (ink as vectors where practical), share via `ShareLink`/`UIActivityViewController`; editor bar item "Share/Export", page menu "Export pages", menu "Insert PDF pages".
- [ ] Backup: `.sheafnote` archive in Core (`Archive/`): zip (own minimal STORE/DEFLATE writer via Compression framework) with `manifest.json` (formatVersion), `library.json`, `ink/<pageID>.drawing`, `assets/<assetID>`, documented byte-exactly in `docs/archive-format.md`; export library or one notebook, import with conflict policy "import as new copies" (never overwrite); optional automatic backup to a Files folder via security-scoped bookmark (daily on launch if changed, keep last N, N configurable); settings section "Import & backup".
- [ ] 500-page PDF opens in a couple of seconds (lazy `PDFDocument`, no page-sized bitmaps up front); measure and record in the unit summary.

### 6.5 ink-tools (worktree `unit/ink-tools`)
- [ ] Core `ShapeRecognizer` (geometric fit: line, arrow, rect, ellipse/circle, triangle, polygon, arc), `LassoGeometry`, `StraightLineFit`, tests first.
- [ ] `LassoTool` (freeform path overlay, selects strokes via `page.ink.strokes(intersecting:)` and elements via `ElementHitTesting`, options: handwriting / images / text toggles), registers selection actions: copy, cut, paste (system pasteboard with private UTI plus plain image), duplicate, delete, recolor, width, "Screenshot selection" (`page.ink.render` + elements), "Convert handwriting to text" (renders selection, calls `HandwritingRecognizer`, inserts a text element via the elements payload codec; original ink kept unless the user chooses Replace, which snapshots first); pastes saved elements via `ElementLibrary.insert`.
- [ ] `ShapesTool` (pick shape kind or auto-recognize, creates `ElementKind.shape` with fill and outline colors, `ShapeElementRenderer` registered for `.shape` incl. hit tester and export drawing); options row with stroke/fill color and width.
- [ ] Draw-and-hold snap in pen mode (`InkTouchObserver`, 0.6 s hold) and "draw straight line" highlighter option (observer for `.highlighter`, option stored in `AppSettingsStore`).

### 6.6 elements (worktree `unit/elements`)
- [ ] Text boxes: `TextElementRenderer` (SwiftUI/`UITextView` editing in place, font, size, color, bold/italic/underline, alignment, background color, resize/move via selection model), `TextTool` (tap to create) with options row; hit tester and export draw (CoreText).
- [ ] Images: `ImageElementRenderer`, `ElementTool` (image picker: Photos via `PhotosPicker`, Files, camera), crop UI, resize, rotate; assets stored via `PageStore.importAsset`.
- [ ] Stickers: Core `StickerCatalog` of own vector stickers (shapes, arrows, tabs, washi-tape strips) drawn from path data (no copied artwork), `StickerElementRenderer`, sticker browser sheet; "Saved elements" tab: browse/rename/delete `ElementLibrary`, insert; selection action "Save as element".
- [ ] Study tape: `TapeTool`, `TapeElementRenderer` (`aboveInk` slot, tap to reveal/hide, export honors `hideTape`), options row with "Hide all / Show all" toggle and tape colors.
- [ ] Registers tools text, element, tape; renderers text, image, sticker, tape.

### 6.7 search (worktree `unit/search`)
- [ ] Core `SearchIndex` (in-memory inverted index + persisted via `Page.recognizedText`, notebook/folder titles, typed text from text elements and text documents, PDF text via PDFKit), tokenizer, ranking, snippets; `OutlineTree`, `LinkTarget` helpers; TDD.
- [ ] `OCRIndexer` background task (via `registerBackgroundTask`): pages whose `inkHash != ocrInkHash`, renders with `PageRenderer`, calls `HandwritingRecognizing`, stores `recognizedText` + `ocrInkHash` (syncs; other device skips), throttled, cancellable, low-priority.
- [ ] UI: library Search destination (whole library) and in-notebook search bar item with result list (page thumbnail, highlighted hit rects from Vision boxes); jump to page.
- [ ] Bookmarks: bar item toggles bookmark on current page; navigator tab "Bookmarks". Outline: navigator tab with user entries + PDF outline, add/rename/delete/reorder entries, tap to jump.
- [ ] Links: `LinkElementRenderer` (`.link` kind, tap navigates to page / notebook / URL with `openURL`), selection action "Link to..." (page picker, notebook picker, URL field) creating a link element over the selection bounds; link also applicable to text elements (payload `linkTarget` decoded from `TextPayload.link`).
- [ ] Settings "Search" (languages, reindex all).

### 6.8 present (worktree `unit/present`)
- [ ] `LaserTool` (`overlayCapturesAll`, dot + fading trail overlay, color/size options; never writes ink), Core `LaserTrailModel` tests first.
- [ ] Presentation mode: menu item "Present", `PresentationSceneDelegate` for the external-display scene (AirPlay/HDMI) showing only the current page without UI via `PageRenderer`-backed live mirror plus laser and zoom-window mirroring; options sheet (hide toolbars on device, show laser, show zoom window); on-device fullscreen presentation when no display is connected.
- [ ] Zoom window: `ZoomWindowTool` (magnified writing strip over the page, drag to move/resize, auto-advance with margin controls, writes through to the page ink), Core `ZoomWindowModel` tests first.
- [ ] Registers tools laser, zoomWindow (both in "more" and primary respectively per GoodNotes layout: laser primary, zoomWindow more).

### 6.9 audio-study (worktree `unit/audio-study`)
- [ ] Recording: `AudioRecorder` wrapper (`AVAudioEngine`/`AVAudioRecorder`, permission flow with clear denied-state UI, interruption handling), notebook menu "Record audio" with recording bar; timeline capture of stroke creation (`AudioStrokeMark`) while recording through ink-change notifications; recording stored as `Asset(audio)` + `AudioRecording`; recordings list per notebook; rename/delete (soft).
- [ ] Playback: player bar, "tap a stroke to seek" in playback mode (hit-test strokes on the current page via `page.ink.strokes(intersecting:)`), highlight strokes as played (overlay).
- [ ] Flashcards: selection action and page menu "Make flashcard" (front and back regions or lasso selection), deck management UI, study session UI.
- [ ] Core `SM2Scheduler`, `StudyState` updates, due queue, tests first; settings "Audio" (default quality).

### 6.10 doc-types (worktree `unit/doc-types`)
- [ ] Whiteboard: factory registered for `.whiteboard` using `EditorScaffold(sizing: .infinite)`, infinite pan/zoom canvas with expanding bounds (Core `CanvasBounds`), library "New whiteboard" item, fit-to-content.
- [ ] Text documents: factory for `.text`, rich text editor (headings, bullet/numbered lists, checklists, bold/italic/underline, inline images via `PageStore.importAsset`), Core `RichTextDocument` codec stored in `Notebook.richText`, library "New text document" item, export hooks via a registered `NotebookMenuItem` only if pdf-io's exporter exposes it (otherwise plain share of text; stated in summary).
- [ ] App lock: `AppLockController` (Face ID/Touch ID/passcode via `LocalAuthentication`, lock on background after grace period, blur cover in app switcher, per-notebook lock flag `Notebook.isLocked` gating open in the router), settings section "App lock"; failure and no-biometrics paths explained to the user; lock never blocks access to data export from settings.

### 6.11 Integrators, reviewers, fixers
- Integrators merge `unit/editor` + `unit/sync` first, then the other seven, in the order pdf-io, ink-tools, elements, search, present, audio-study, doc-types; after each merge run `xcodegen generate` and `scripts/verify.sh integrate`. They only fix merge conflicts and compile errors, and add interface members additively.
- Reviewers check against section 7 plus the anti-goals (data loss paths, silent catches, network use, third-party code, missing accessibility labels, untranslated strings); fixers follow reviewer reports.
- Final state: app builds for simulator, `swift test` passes, app tests pass, UI tests pass; anything not done is listed plainly (known external gaps: real CloudKit round trip, Apple Pencil hardware feel, device builds and signing).

## 7. Design coverage table (design bullet -> unit)

| Design bullet | Unit |
|---|---|
| Library: iPad split view, sidebar, cover grid, folder tiles, toolbar (New, sort, grid/list, Select) | foundation |
| Library: iPhone stack, two-column grid | foundation |
| Library: context menus (rename, cover, duplicate, move, favorite, delete) | foundation |
| Library: context menu "Export" entry | pdf-io |
| Library: sidebar "Search" destination | search |
| New notebook sheet: title, ~20 covers, paper carousel, colors, orientation, sizes (A4/Letter/A5/square) | foundation |
| Editor: top bar layout, tool row, preset row, own toolbar (not PKToolPicker), Pencil double-tap/squeeze, finger/Pencil-only | editor |
| Editor: gray canvas, pinch zoom, vertical continuous / horizontal paged, iPhone bottom toolbar | editor |
| Editor: iPad tabs, Split View, Stage Manager windows | editor |
| P1 Library: nested folders, notebooks, favorites, sort, grid/list, Recently Deleted (30 d, restore), multi-select move/delete | foundation |
| P1 New notebook with covers, templates, sizes, colors, orientation | foundation |
| P1 Change a page's template later | editor |
| P1 Pen with PencilKit inks, pressure, color and width presets | editor |
| P1 Highlighter | editor |
| P1 Highlighter "draw straight line" option | ink-tools |
| P1 Eraser (whole-stroke, partial, sizes, highlighter-only, switch back) | editor |
| P1 Undo and redo per notebook | editor |
| P1 Pages: add, duplicate, delete, reorder, go to page | editor |
| P1 Pencil double-tap and squeeze switching; finger or Pencil only | editor |
| P1 iCloud sync of everything above; local-only mode | sync |
| P2 Import PDF (Files, share sheet, drag and drop) as notebook or into existing; images as pages | pdf-io |
| P2 Mark up PDF pages (PDF as background, ink on top) | pdf-io |
| P2 Export notebook/pages as PDF (with/without backgrounds) or images; share sheet | pdf-io |
| P2 Lasso: select, move/resize/rotate/recolor/width, copy/cut/paste/duplicate/delete, screenshot, convert handwriting to text, lasso pick-up options | ink-tools |
| P2 Shapes tool and shape fill/outline colors; draw-and-hold snap | ink-tools |
| P2 Text boxes | elements |
| P2 Images (insert from Photos/Files/camera; crop, resize, rotate, move) | elements |
| P2 Zoom window | present |
| P3 Search (handwriting OCR, typed text, PDF text, titles; result thumbnails with highlights) | search |
| P3 Bookmarks and bookmarks list | search |
| P3 Outline (user + PDF's own) | search |
| P3 Links (to page, notebook, URL) | search |
| P3 Scroll direction per notebook | editor |
| P4 Elements and stickers (built-in set, save lasso selection as element) | elements |
| P4 Study tape with hide/show all | elements |
| P4 Laser pointer | present |
| P4 Presentation mode (external display / AirPlay) | present |
| P4 Audio recording and tap-stroke-to-seek playback | audio-study |
| P4 Flashcards with spaced repetition | audio-study |
| P4 Whiteboards | doc-types |
| P4 Text documents | doc-types |
| P4 App lock (app and per notebook) | doc-types |
| P4 Backup: `.sheafnote` export/import (library or one notebook), documented format | pdf-io |
| P4 Optional automatic backup to a Files folder | pdf-io |
| Build: SwiftData schema for all phases, local store, soft deletes, 30-day purge | foundation |
| Build: CKSyncEngine sync layer, fractional page order sync, record mapping | sync |
| Build: conflicts, stroke merge, Recovered area (30 days) | sync |
| Build: signing out / account switch never deletes local data | sync |
| Build: search index OCR on changed pages, text synced on `Page` | search |
| Build: templates as vectors (crisp, export cleanly) | foundation |
| Build: page layer stack and ink-above-images ordering | editor |
| Build: handwriting recognition service (Vision, on-device) | foundation |
| Owner: own icon, covers, colors, no GoodNotes assets | foundation (icon, covers), elements (stickers) |
| Owner: privacy manifest, String Catalog, VoiceOver and Dynamic Type set-up | foundation (setup), every unit (its own screens) |
| Owner: Apple's PencilKit inks under Apple names | editor |
| Testing rules: test-first logic, 80% Core coverage, XCUITest main flows (create notebook, write, add page, search, export) | foundation (create notebook), editor (write, add page), search (search), pdf-io (export) |
