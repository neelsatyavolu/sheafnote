import SwiftUI
import SheafnoteCore

/// Navigator tab "Flashcards": decks of this notebook with due counts, study and card management.
struct FlashcardsTab: View {
    let editor: any EditorContext
    @State private var decks: [DeckSummary] = []
    @State private var errorMessage: String?
    @State private var studying: StudySessionModel?
    @State private var renamingDeck: String?
    @State private var newName = ""

    private var store: StudyStore { AudioStudyHub.shared.session(for: editor).study }
    private var notebookID: UUID { editor.notebook.id }

    var body: some View {
        Group {
            if let studying {
                studySession(studying)
            } else {
                deckList
            }
        }
        .task { reload() }
    }

    /// The session replaces the deck list in place (no extra presentation on top of the navigator sheet).
    private func studySession(_ model: StudySessionModel) -> some View {
        NavigationStack {
            StudySessionView(model: model, onFinish: { studying = nil; reload() })
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { studying = nil; reload() } label: { Text("Close", tableName: "AudioStudy") }
                            .accessibilityIdentifier("study.close")
                    }
                }
        }
    }

    private var deckList: some View {
        NavigationStack {
            List {
                if let errorMessage { Text(errorMessage).foregroundStyle(.red).accessibilityIdentifier("flashcards.error") }
                if decks.isEmpty {
                    emptyState
                } else {
                    Section {
                        Button { study(deck: nil) } label: {
                            Label { Text("Study all due cards", tableName: "AudioStudy") } icon: { Image(systemName: "rectangle.stack") }
                        }
                        .disabled(decks.allSatisfy { $0.due == 0 })
                        .accessibilityIdentifier("flashcards.studyAll")
                    }
                    Section { ForEach(decks) { deckRow($0) } } header: { Text("Decks", tableName: "AudioStudy") }
                }
            }
            .navigationTitle(Text("Flashcards", tableName: "AudioStudy"))
            .navigationDestination(for: String.self) { deck in
                DeckCardsView(store: store, notebookID: notebookID, deck: deck, onChange: reload)
            }
            .alert(Text("Rename deck", tableName: "AudioStudy"), isPresented: Binding(
                get: { renamingDeck != nil }, set: { if !$0 { renamingDeck = nil } })) {
                TextField(text: $newName) { Text("Name", tableName: "AudioStudy") }
                Button { rename() } label: { Text("Rename", tableName: "AudioStudy") }
                Button(role: .cancel) {} label: { Text("Cancel", tableName: "AudioStudy") }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "rectangle.on.rectangle.angled").font(.largeTitle).foregroundStyle(.secondary)
            Text("No flashcards yet", tableName: "AudioStudy").font(.headline)
            Text("Select writing with the lasso and choose Make flashcard, or use Make flashcards in a page's menu.",
                 tableName: "AudioStudy")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("flashcards.empty")
    }

    private func deckRow(_ deck: DeckSummary) -> some View {
        HStack {
            NavigationLink(value: deck.name) {
                VStack(alignment: .leading) {
                    Text(deck.name).font(.headline)
                    Text("\(deck.total) cards, \(deck.due) due", tableName: "AudioStudy").font(.caption).foregroundStyle(.secondary)
                }
            }
            Button { study(deck: deck.name) } label: { Text("Study", tableName: "AudioStudy") }
                .buttonStyle(.borderless)
                .disabled(deck.due == 0)
                .accessibilityIdentifier("flashcards.study.\(deck.name)")
        }
        .contextMenu {
            Button { newName = deck.name; renamingDeck = deck.name } label: {
                Label { Text("Rename", tableName: "AudioStudy") } icon: { Image(systemName: "pencil") }
            }
        }
        .accessibilityIdentifier("flashcards.deck.\(deck.name)")
    }

    private func reload() {
        do {
            decks = try store.decks(in: notebookID)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func study(deck: String?) {
        do {
            let cards = try store.dueCards(in: notebookID, deck: deck)
            studying = StudySessionModel(cards: cards, store: store)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func rename() {
        guard let old = renamingDeck else { return }
        do {
            try store.renameDeck(old, to: newName, in: notebookID)
        } catch {
            errorMessage = error.localizedDescription
        }
        reload()
    }
}

extension StudySessionModel: Identifiable, Hashable {
    nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }
    nonisolated static func == (l: StudySessionModel, r: StudySessionModel) -> Bool { l === r }
    nonisolated func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}

/// Cards of one deck: preview, move to another deck, delete (soft).
struct DeckCardsView: View {
    let store: StudyStore
    let notebookID: UUID
    let deck: String
    let onChange: () -> Void
    @State private var cards: [Flashcard] = []
    @State private var errorMessage: String?
    @State private var deleting: Flashcard?

    var body: some View {
        List {
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            ForEach(cards) { card in
                HStack(spacing: 10) {
                    thumb(card.frontImage, label: Text("Front", tableName: "AudioStudy"))
                    thumb(card.backImage, label: Text("Back", tableName: "AudioStudy"))
                    Spacer()
                }
                .swipeActions {
                    Button(role: .destructive) { deleting = card } label: {
                        Label { Text("Delete", tableName: "AudioStudy") } icon: { Image(systemName: "trash") }
                    }
                }
                .accessibilityElement(children: .contain)
            }
        }
        .navigationTitle(deck)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(Text("Delete this flashcard?", tableName: "AudioStudy"), isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button(role: .destructive) { delete() } label: { Text("Delete", tableName: "AudioStudy") }
        } message: {
            Text("The notebook's writing is not affected.", tableName: "AudioStudy")
        }
        .task { reload() }
    }

    private func thumb(_ data: Data, label: Text) -> some View {
        Group {
            if let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 80)
                    .background(Color.white).border(Color.secondary.opacity(0.4))
            } else {
                Image(systemName: "photo")
            }
        }
        .accessibilityLabel(label)
    }

    private func reload() {
        do {
            cards = try store.cards(in: notebookID, deck: deck)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete() {
        guard let card = deleting else { return }
        do { try store.softDelete(cardID: card.id) } catch { errorMessage = error.localizedDescription }
        reload()
        onChange()
    }
}
