import SwiftUI

/// The text Vision read from the handwriting, to check and fix before it goes onto the page.
struct ConvertTextSheet: View {
    @State var text: String
    let canReplace: Bool
    let insert: (String) -> Void
    let replace: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 120)
                        .accessibilityLabel(Text("Recognized text", tableName: "InkTools"))
                        .accessibilityIdentifier("inktools.convert.text")
                } footer: {
                    Text("Check the text before adding it. Your handwriting stays on the page unless you replace it.", tableName: "InkTools")
                }
                Section {
                    Button { insert(trimmed); dismiss() } label: { Text("Add Text Below Handwriting", tableName: "InkTools") }
                        .disabled(trimmed.isEmpty)
                        .accessibilityIdentifier("inktools.convert.insert")
                    if canReplace {
                        Button { replace(trimmed); dismiss() } label: { Text("Replace Handwriting with Text", tableName: "InkTools") }
                            .disabled(trimmed.isEmpty)
                            .accessibilityIdentifier("inktools.convert.replace")
                    }
                } footer: {
                    if canReplace { Text("Replacing can be undone, and a copy of the page is kept for 30 days under Recovered pages in the iCloud Sync settings.", tableName: "InkTools") }
                }
            }
            .navigationTitle(Text("Convert to Text", tableName: "InkTools"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Text("Cancel", tableName: "InkTools") } }
            }
        }
    }
}
