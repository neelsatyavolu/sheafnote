import SwiftUI
import SheafnoteCore

/// Settings section "Search" (order 40): handwriting language and rebuilding the index.
enum SearchSettingsSection {
    static func section(service: SearchService) -> SettingsSection {
        SettingsSection(id: "search", order: 40, title: LocalizedStringResource("Search", table: "Search"),
                        symbolName: "magnifyingglass") { _ in
            AnyView(SearchSettingsContent(service: service))
        }
    }
}

private struct SearchSettingsContent: View {
    let service: SearchService

    @State private var language = ""
    @State private var pending = 0
    @State private var confirmRebuild = false
    @State private var errorMessage: String?
    private let languages = SearchPreferences.supportedLanguages()

    private var preferences: SearchPreferences { SearchPreferences(settings: service.services.settings) }

    var body: some View {
        Section {
            Picker(selection: Binding(get: { language }, set: setLanguage)) {
                Text("Automatic", tableName: "Search").tag("")
                ForEach(languages, id: \.self) { id in
                    Text(Locale.current.localizedString(forIdentifier: id) ?? id).tag(id)
                }
            } label: { Text("Handwriting Language", tableName: "Search") }
            .accessibilityIdentifier("settings.search.language")
        } header: {
            Text("Search", tableName: "Search").paperHeader()
        } footer: {
            Text("Sheafnote reads your handwriting on this device so you can search it. Automatic tries English first. A new language applies to pages read from now on; rebuild the index to apply it to everything.", tableName: "Search")
        }
        Section {
            LabeledContent {
                Text("\(pending)").monospacedDigit()
            } label: { Text("Pages not read yet", tableName: "Search") }
            if service.ocr.failedCount > 0 {
                LabeledContent {
                    Text("\(service.ocr.failedCount)").monospacedDigit()
                } label: { Text("Pages that couldn't be read", tableName: "Search") }
            }
            Button(role: .destructive) { confirmRebuild = true } label: { Text("Rebuild Search Index", tableName: "Search") }
                .accessibilityIdentifier("settings.search.rebuild")
        } footer: {
            Text("Rebuilding reads every page again. Your notes aren't changed, and old search results stay until the new ones are ready.", tableName: "Search")
        }
        .task { language = preferences.languages.first ?? ""; pending = service.ocr.countPending() }
        .confirmationDialog(Text("Rebuild the search index?", tableName: "Search"), isPresented: $confirmRebuild, titleVisibility: .visible) {
            Button(role: .destructive) { rebuild() } label: { Text("Rebuild", tableName: "Search") }
        } message: {
            Text("This can take a while for large libraries and uses battery.", tableName: "Search")
        }
        .alert(Text("Something went wrong", tableName: "Search"),
               isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button { errorMessage = nil } label: { Text("OK", tableName: "Search") }
        } message: { Text(errorMessage ?? "") }
    }

    private func setLanguage(_ id: String) {
        language = id
        preferences.languages = id.isEmpty ? [] : [id]
    }

    private func rebuild() {
        do {
            try service.rebuild()
            pending = service.ocr.countPending()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
