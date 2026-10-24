import SwiftUI
import SheafnoteCore

struct ChangeCoverSheet: View {
    let notebookID: UUID

    @Environment(LibrarySession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var selected: String
    @ScaledMetric private var cellWidth: CGFloat = 100

    init(notebookID: UUID) {
        self.notebookID = notebookID
        _selected = State(initialValue: "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                CoverGrid(selectedID: $selected, cellWidth: cellWidth)
                    .padding()
            }
            .navigationTitle("Change Cover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        LibraryActions(session: session).setCover(notebookID, CoverSpec(coverID: selected))
                        dismiss()
                    }
                    .disabled(selected.isEmpty).accessibilityIdentifier("changeCover.done")
                }
            }
            .onAppear {
                if selected.isEmpty, let nb = session.services.library.notebook(id: notebookID) { selected = nb.cover.coverID }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Grid of every built-in cover with a selection ring.
struct CoverGrid: View {
    @Binding var selectedID: String
    let cellWidth: CGFloat

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: cellWidth), spacing: 16)], spacing: 16) {
            ForEach(CoverCatalog.all) { cover in
                Button { selectedID = cover.id } label: { CoverChoice(definition: cover, isSelected: selectedID == cover.id) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(cover.title))
                    .accessibilityAddTraits(selectedID == cover.id ? [.isButton, .isSelected] : .isButton)
                    .accessibilityIdentifier("cover.\(cover.id)")
            }
        }
    }
}

struct CoverChoice: View {
    let definition: CoverDefinition
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            NotebookCoverView(cover: CoverSpec(coverID: definition.id))
                .padding(4)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor, lineWidth: isSelected ? 3 : 0))
            Text(definition.title).font(.caption).foregroundStyle(isSelected ? Color.accentColor : .secondary)
        }
    }
}
