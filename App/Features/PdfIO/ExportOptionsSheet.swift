import SwiftUI
import SheafnoteCore

/// "Export": pick pages and a format, render, then hand the files to the share sheet.
struct ExportOptionsSheet: View {
    @State var model: ExportModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if model.availablePageChoices.count > 1 { pagesSection }
                formatSection
                optionsSection
                actionSection
            }
            .navigationTitle(Text("Export", tableName: "PdfIO"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text(model.isWorking ? "Cancel" : "Done", tableName: "PdfIO") }
                        .accessibilityIdentifier("export.close")
                }
            }
            .onDisappear { model.dismiss() }
        }
        .accessibilityIdentifier("export.sheet")
    }

    // MARK: Sections

    private var pagesSection: some View {
        Section {
            Picker(selection: $model.pageChoice) {
                ForEach(model.availablePageChoices, id: \.self) { choice in
                    Text(title(for: choice)).tag(choice)
                }
            } label: { Text("Pages", tableName: "PdfIO") }
            .accessibilityIdentifier("export.pages")
            if model.pageChoice == .range {
                TextField(text: $model.rangeText, prompt: Text("1-3, 5", tableName: "PdfIO")) { Text("Page numbers", tableName: "PdfIO") }
                    .keyboardType(.numbersAndPunctuation)
                    .accessibilityIdentifier("export.range")
                if !model.rangeText.isEmpty, model.parsedRange == nil {
                    Text("Enter page numbers from 1 to \(model.pageCount), like 1-3, 5.", tableName: "PdfIO")
                        .font(.footnote).foregroundStyle(.red)
                }
            }
        }
    }

    private var formatSection: some View {
        Section {
            Picker(selection: $model.kind) {
                ForEach(model.availableKinds) { kind in Text(title(for: kind)).tag(kind) }
            } label: { Text("Format", tableName: "PdfIO") }
            .pickerStyle(.menu)
            .accessibilityIdentifier("export.format")
        } footer: {
            Text(footer(for: model.kind))
        }
    }

    @ViewBuilder private var optionsSection: some View {
        if model.supportsBackgroundOption {
            Section {
                Toggle(isOn: $model.includeBackground) { Text("Include page backgrounds", tableName: "PdfIO") }
                    .accessibilityIdentifier("export.background")
                if model.usesImages {
                    Picker(selection: $model.imageScale) {
                        Text("Standard", tableName: "PdfIO").tag(CGFloat(1))
                        Text("High", tableName: "PdfIO").tag(CGFloat(2))
                        Text("Maximum", tableName: "PdfIO").tag(CGFloat(3))
                    } label: { Text("Image quality", tableName: "PdfIO") }
                }
            } footer: {
                Text("Backgrounds are the paper pattern and any imported PDF or image behind your writing.", tableName: "PdfIO")
            }
        }
    }

    @ViewBuilder private var actionSection: some View {
        Section {
            switch model.phase {
            case .idle:
                Button { model.start() } label: { Text("Export", tableName: "PdfIO") }
                    .disabled(!model.canStart)
                    .accessibilityIdentifier("export.start")
            case .working(let fraction):
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: fraction) { Text("Exporting…", tableName: "PdfIO") }
                        .accessibilityIdentifier("export.progress")
                    Button(role: .cancel) { model.cancel() } label: { Text("Stop", tableName: "PdfIO") }
                }
            case .ready(let output):
                readyRows(output)
            case .failed(let message):
                Label { Text(message) } icon: { Image(systemName: "exclamationmark.triangle") }
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("export.error")
                Button { model.start() } label: { Text("Try Again", tableName: "PdfIO") }
            }
        }
    }

    @ViewBuilder private func readyRows(_ output: ExportOutput) -> some View {
        Label { Text("Export ready", tableName: "PdfIO") } icon: {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        }
        .accessibilityIdentifier("export.result")
        LabeledContent { Text(output.pageCount, format: .number) } label: { Text("Pages exported", tableName: "PdfIO") }
            .accessibilityIdentifier("export.pageCount")
        ForEach(output.files, id: \.self) { url in
            LabeledContent(url.lastPathComponent) { Text(fileSize(url)).foregroundStyle(.secondary) }
                .accessibilityElement(children: .combine)
        }
        ShareLink(items: output.files) { Label { Text("Share or Save…", tableName: "PdfIO") } icon: { Image(systemName: "square.and.arrow.up") } }
            .accessibilityIdentifier("export.share")
        Button { model.start() } label: { Text("Export Again", tableName: "PdfIO") }
    }

    // MARK: Text

    private func title(for choice: ExportPageChoice) -> LocalizedStringResource {
        switch choice {
        case .whole: LocalizedStringResource("Entire notebook", table: "PdfIO")
        case .current: LocalizedStringResource("Current page", table: "PdfIO")
        case .selected: LocalizedStringResource("Selected pages (\(model.selectedPageIDs.count))", table: "PdfIO")
        case .range: LocalizedStringResource("Page range", table: "PdfIO")
        }
    }

    private func title(for kind: ExportKind) -> LocalizedStringResource {
        switch kind {
        case .pdf: LocalizedStringResource("PDF", table: "PdfIO")
        case .png: LocalizedStringResource("Images (PNG)", table: "PdfIO")
        case .jpeg: LocalizedStringResource("Images (JPEG)", table: "PdfIO")
        case .archive: LocalizedStringResource("Sheafnote backup", table: "PdfIO")
        }
    }

    private func footer(for kind: ExportKind) -> LocalizedStringResource {
        switch kind {
        case .pdf: LocalizedStringResource("One PDF per notebook. Pages keep their size.", table: "PdfIO")
        case .png, .jpeg: LocalizedStringResource("One image per page.", table: "PdfIO")
        case .archive: LocalizedStringResource("Everything in the notebook, including writing, attachments and outlines. Open it again in Sheafnote on any device.", table: "PdfIO")
        }
    }

    private func fileSize(_ url: URL) -> String {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
