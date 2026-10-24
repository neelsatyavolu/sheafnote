import SwiftUI
import SheafnoteCore

/// Drives the card maker: loads the page picture and cuts the front and back regions out of it.
@MainActor @Observable
final class FlashcardMaker {
    enum Side: String, CaseIterable, Identifiable { case front, back; var id: String { rawValue } }

    let editor: any EditorContext
    let pageID: UUID
    let pageSize: CGSize
    var regions: CardRegions
    var side: Side = .front
    var deck: String
    private(set) var pageImage: UIImage?
    private(set) var errorMessage: String?
    private(set) var isSaving = false

    init(editor: any EditorContext, pageID: UUID, pageSize: CGSize, selection: CGRect?, deck: String) {
        self.editor = editor
        self.pageID = pageID
        self.pageSize = pageSize
        self.deck = deck
        regions = selection.map { CardRegions.initial(forSelection: $0, in: pageSize) } ?? CardRegions.initial(in: pageSize)
    }

    func loadPage() async {
        do {
            let image = try await editor.services.pageRenderer.renderImage(pageID: pageID, rect: nil, scale: 1, options: .screen)
            pageImage = UIImage(cgImage: image)
        } catch {
            errorMessage = String(localized: "The page could not be shown (\(error.localizedDescription)).", table: "AudioStudy")
        }
    }

    func region(_ side: Side) -> CGRect { side == .front ? regions.front : regions.back }

    func setRegion(_ rect: CGRect, for side: Side) {
        let clamped = CardRegions.clamp(rect, to: pageSize)
        if side == .front { regions.front = clamped } else { regions.back = clamped }
    }

    /// Cuts both regions from the page and stores the card. Returns true when the card was saved.
    func save() async -> Bool {
        isSaving = true
        defer { isSaving = false }
        do {
            let r = regions.clamped(to: pageSize)
            let front = try await png(of: r.front)
            let back = try await png(of: r.back)
            let store = AudioStudyHub.shared.session(for: editor).study
            try store.createCard(notebookID: editor.notebook.id, deck: deck, sourcePageID: pageID, frontImage: front, backImage: back)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func png(of rect: CGRect) async throws -> Data {
        let cg = try await editor.services.pageRenderer.renderImage(pageID: pageID, rect: rect, scale: 2, options: .screen)
        guard let data = UIImage(cgImage: cg).pngData() else {
            throw StoreError.invalid(String(localized: "The card picture could not be made.", table: "AudioStudy"))
        }
        return data
    }
}

struct MakeFlashcardSheet: View {
    @State var maker: FlashcardMaker
    let decks: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker(selection: $maker.side) {
                    Text("Front", tableName: "AudioStudy").tag(FlashcardMaker.Side.front)
                    Text("Back", tableName: "AudioStudy").tag(FlashcardMaker.Side.back)
                } label: { Text("Region", tableName: "AudioStudy") }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("flashcard.side")
                Text("Drag the colored box over the writing for this side. Drag its corner to resize.", tableName: "AudioStudy")
                    .font(.footnote).foregroundStyle(.secondary)
                GeometryReader { geo in canvas(in: geo.size) }
                deckField
                if let error = maker.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(.red).accessibilityIdentifier("flashcard.error")
                }
            }
            .padding()
            .navigationTitle(Text("Make flashcard", tableName: "AudioStudy"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel", tableName: "AudioStudy") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { if await maker.save() { dismiss() } } } label: { Text("Add card", tableName: "AudioStudy") }
                        .disabled(maker.pageImage == nil || maker.isSaving)
                        .accessibilityIdentifier("flashcard.save")
                }
            }
        }
        .task { await maker.loadPage() }
    }

    private var deckField: some View {
        HStack {
            TextField(text: $maker.deck) { Text("Deck", tableName: "AudioStudy") }
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("flashcard.deck")
            if !decks.isEmpty {
                Menu {
                    ForEach(decks, id: \.self) { name in Button(name) { maker.deck = name } }
                } label: { Image(systemName: "chevron.up.chevron.down") }
                .accessibilityLabel(Text("Choose existing deck", tableName: "AudioStudy"))
            }
        }
    }

    @ViewBuilder
    private func canvas(in available: CGSize) -> some View {
        let size = maker.pageSize
        let scale = min(available.width / max(size.width, 1), available.height / max(size.height, 1))
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        ZStack(alignment: .topLeading) {
            if let image = maker.pageImage {
                Image(uiImage: image).resizable().frame(width: fitted.width, height: fitted.height)
            } else {
                ProgressView().frame(width: fitted.width, height: fitted.height)
            }
            RegionBox(maker: maker, side: .front, scale: scale, color: .blue)
            RegionBox(maker: maker, side: .back, scale: scale, color: .green)
        }
        .frame(width: fitted.width, height: fitted.height)
        .border(Color.secondary.opacity(0.4))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A draggable, resizable box over the page picture. The active side is solid, the other one faint.
private struct RegionBox: View {
    let maker: FlashcardMaker
    let side: FlashcardMaker.Side
    let scale: CGFloat
    let color: Color
    @State private var dragStart: CGRect?
    @State private var resizeStart: CGRect?

    private var rect: CGRect { maker.region(side) }
    private var isActive: Bool { maker.side == side }
    private var name: Text { side == .front ? Text("Front", tableName: "AudioStudy") : Text("Back", tableName: "AudioStudy") }

    var body: some View {
        let r = rect
        ZStack(alignment: .bottomTrailing) {
            Rectangle().fill(color.opacity(isActive ? 0.18 : 0.08))
            Rectangle().stroke(color, lineWidth: isActive ? 3 : 1.5)
            name.font(.caption.bold()).foregroundStyle(color).padding(4).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if isActive {
                Circle().fill(color).frame(width: 22, height: 22).padding(2)
                    .gesture(DragGesture().onChanged { v in
                        let start = resizeStart ?? rect
                        resizeStart = start
                        maker.setRegion(CGRect(x: start.minX, y: start.minY, width: start.width + v.translation.width / scale,
                                               height: start.height + v.translation.height / scale), for: side)
                    }.onEnded { _ in resizeStart = nil })
                    .accessibilityHidden(true)
            }
        }
        .frame(width: r.width * scale, height: r.height * scale)
        .contentShape(Rectangle())
        .gesture(DragGesture().onChanged { v in
            maker.side = side
            let start = dragStart ?? rect
            dragStart = start
            maker.setRegion(start.offsetBy(dx: v.translation.width / scale, dy: v.translation.height / scale), for: side)
        }.onEnded { _ in dragStart = nil })
        .offset(x: r.minX * scale, y: r.minY * scale)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityAction(named: Text("Select", tableName: "AudioStudy")) { maker.side = side }
        .accessibilityAction(named: Text("Move up", tableName: "AudioStudy")) { nudge(0, -20) }
        .accessibilityAction(named: Text("Move down", tableName: "AudioStudy")) { nudge(0, 20) }
        .accessibilityAction(named: Text("Move left", tableName: "AudioStudy")) { nudge(-20, 0) }
        .accessibilityAction(named: Text("Move right", tableName: "AudioStudy")) { nudge(20, 0) }
        .accessibilityAction(named: Text("Make taller", tableName: "AudioStudy")) { grow(0, 20) }
        .accessibilityAction(named: Text("Make wider", tableName: "AudioStudy")) { grow(20, 0) }
        .accessibilityIdentifier("flashcard.region.\(side.rawValue)")
    }

    private func nudge(_ dx: CGFloat, _ dy: CGFloat) { maker.setRegion(rect.offsetBy(dx: dx, dy: dy), for: side) }
    private func grow(_ dw: CGFloat, _ dh: CGFloat) {
        maker.setRegion(CGRect(x: rect.minX, y: rect.minY, width: rect.width + dw, height: rect.height + dh), for: side)
    }
}
