import SwiftUI
import SheafnoteCore

struct LinkChoice: Sendable {
    let target: LinkTarget
    let label: String
}

/// Where should the link go: a page, a notebook, or a web address. Calls `onChoose` once, or `onCancel` if the
/// sheet is dismissed without a choice.
struct LinkPickerSheet: View {
    enum Mode: Hashable { case page, notebook, web }

    let services: AppServices
    let notebookID: UUID
    let onChoose: (LinkChoice) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var mode = Mode.page
    @State private var didChoose = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker(selection: $mode) {
                    Text("Page", tableName: "Search").tag(Mode.page)
                    Text("Notebook", tableName: "Search").tag(Mode.notebook)
                    Text("Web", tableName: "Search").tag(Mode.web)
                } label: { Text("Link type", tableName: "Search") }
                .pickerStyle(.segmented)
                .padding()
                .accessibilityIdentifier("search.link.mode")
                content
            }
            .navigationTitle(Text("Link To", tableName: "Search"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel", tableName: "Search") }
                        .accessibilityIdentifier("search.link.cancel")
                }
            }
        }
        .onDisappear { if !didChoose { onCancel() } }
        .accessibilityIdentifier("search.link.picker")
    }

    @ViewBuilder private var content: some View {
        switch mode {
        case .page:
            LinkPageGrid(services: services, notebookID: notebookID, choose: choose)
        case .notebook:
            LinkNotebookList(services: services, choose: choose)
        case .web:
            LinkWebForm(choose: choose)
        }
    }

    private func choose(_ choice: LinkChoice) {
        didChoose = true
        onChoose(choice)
        dismiss()
    }
}

/// Pages of one notebook as thumbnails.
struct LinkPageGrid: View {
    let services: AppServices
    let notebookID: UUID
    let choose: (LinkChoice) -> Void
    var includesWholeNotebook = false
    var notebookTitle = ""

    @State private var pageIDs: [UUID] = []
    @State private var failure: String?
    private let columns = [GridItem(.adaptive(minimum: 110, maximum: 170), spacing: 14)]

    var body: some View {
        ScrollView {
            if includesWholeNotebook {
                Button {
                    choose(LinkChoice(target: .notebook(notebookID), label: notebookTitle))
                } label: {
                    Label { Text("Open the Notebook", tableName: "Search") } icon: { Image(systemName: "book.closed") }
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal)
                .accessibilityIdentifier("search.link.wholeNotebook")
            }
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(Array(pageIDs.enumerated()), id: \.element) { index, id in
                    Button {
                        choose(LinkChoice(target: .page(id), label: String(localized: "Page \(index + 1)", table: "Search")))
                    } label: {
                        VStack(spacing: 6) {
                            PageThumbnailView(pageID: id, services: services, width: 240)
                            Text("\(index + 1)").font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Page \(index + 1)", tableName: "Search"))
                    .accessibilityIdentifier("search.link.page.\(index + 1)")
                }
            }
            .padding()
        }
        .overlay { if let failure { Text(failure).foregroundStyle(.secondary).padding() } }
        .task {
            do { pageIDs = try services.pages.orderedPages(of: notebookID).map(\.id) } catch { failure = error.localizedDescription }
        }
    }
}

struct LinkNotebookList: View {
    let services: AppServices
    let choose: (LinkChoice) -> Void

    @State private var notebooks: [Notebook] = []
    @State private var failure: String?

    var body: some View {
        List(notebooks, id: \.id) { notebook in
            NavigationLink {
                destination(for: notebook)
            } label: {
                Label(notebook.title, systemImage: notebook.kind == .text ? "doc.text" : "book.closed")
            }
            .accessibilityIdentifier("search.link.notebook.\(notebook.title)")
        }
        .overlay { if let failure { Text(failure).foregroundStyle(.secondary).padding() } }
        .task {
            do {
                notebooks = try services.library.allNotebooks().filter { $0.deletedAt == nil }
                    .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            } catch { failure = error.localizedDescription }
        }
    }

    @ViewBuilder
    private func destination(for notebook: Notebook) -> some View {
        if notebook.kind == .text {
            Color.clear.onAppear { choose(LinkChoice(target: .notebook(notebook.id), label: notebook.title)) }
        } else {
            LinkPageGrid(services: services, notebookID: notebook.id, choose: choose,
                         includesWholeNotebook: true, notebookTitle: notebook.title)
                .navigationTitle(notebook.title)
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct LinkWebForm: View {
    let choose: (LinkChoice) -> Void

    @State private var text = ""
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                TextField(text: $text) { Text("example.com", tableName: "Search") }
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(commit)
                    .onChange(of: text) { _, _ in message = nil }
                    .accessibilityIdentifier("search.link.url")
            } header: {
                Text("Web Address", tableName: "Search")
            } footer: {
                if let message { Text(message).foregroundStyle(.red) }
            }
            Section {
                Button { commit() } label: { Text("Add Link", tableName: "Search") }
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("search.link.addURL")
            }
        }
    }

    private func commit() {
        switch LinkTargetCodec.parseURL(text) {
        case .success(let target):
            let label: String
            if case .url(let url) = target { label = url.host ?? url.absoluteString } else { label = text }
            choose(LinkChoice(target: target, label: label))
        case .failure(let error):
            message = error.localizedDescription
        }
    }
}
