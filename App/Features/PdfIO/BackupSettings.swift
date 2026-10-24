import SwiftUI
import UniformTypeIdentifiers
import SheafnoteCore

enum BackupSettings {
    /// "Import & backup", order 30 in Settings.
    @MainActor
    static func section(controller: AutoBackupController) -> SettingsSection {
        SettingsSection(id: "pdfio.backup", order: 30, title: LocalizedStringResource("Import & Backup", table: "PdfIO"),
                        symbolName: "externaldrive") { services in
            AnyView(BackupSettingsContent(controller: controller, services: services))
        }
    }
}

private struct BackupSettingsContent: View {
    let controller: AutoBackupController
    let services: AppServices
    @State private var showFolderPicker = false
    @State private var showRestorePicker = false
    @State private var showLibraryExport = false
    @State private var restoreResult: RestoreResult?
    @State private var errorMessage: String?
    @State private var isRestoring = false

    var body: some View {
        autoBackupSection
        transferSection
            .sheet(isPresented: $showLibraryExport) { LibraryExportSheet(services: services) }
            .sheet(item: $restoreResult) { result in
                ImportSummarySheet(notebooks: result.summary.notebookIDs.count, pages: result.summary.pageCount)
            }
            .alert(Text("Something went wrong", tableName: "PdfIO"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button(role: .cancel) {} label: { Text("OK", tableName: "PdfIO") }
            } message: { Text(errorMessage ?? "") }
    }

    // MARK: Automatic backup

    private var autoBackupSection: some View {
        Section {
            Toggle(isOn: Binding(get: { controller.settings.isEnabled }, set: { controller.setEnabled($0) })) {
                Text("Automatic backup", tableName: "PdfIO")
            }
            .disabled(!controller.hasFolder)
            .accessibilityIdentifier("backup.toggle")
            Button { showFolderPicker = true } label: {
                LabeledContent {
                    Text(controller.folderName ?? String(localized: "None", table: "PdfIO")).foregroundStyle(.secondary)
                } label: { Text("Backup folder", tableName: "PdfIO") }
            }
            .accessibilityIdentifier("backup.folder")
            Stepper(value: Binding(get: { controller.settings.clampedKeepCount }, set: { controller.setKeepCount($0) }),
                    in: AutoBackupSettings.keepRange) {
                LabeledContent { Text(controller.settings.clampedKeepCount, format: .number) } label: { Text("Keep newest backups", tableName: "PdfIO") }
            }
            .accessibilityIdentifier("backup.keep")
            Button { Task { await controller.backUpNow() } } label: { Text("Back Up Now", tableName: "PdfIO") }
                .disabled(!controller.hasFolder || controller.isRunning)
                .accessibilityIdentifier("backup.now")
            if controller.isRunning { ProgressView { Text("Backing up…", tableName: "PdfIO") } }
            if let last = controller.settings.lastBackupAt {
                LabeledContent { Text(last, format: .dateTime.day().month().year().hour().minute()) } label: { Text("Last backup", tableName: "PdfIO") }
            }
            if let failure = controller.settings.lastError {
                Label { Text(failure) } icon: { Image(systemName: "exclamationmark.triangle") }
                    .foregroundStyle(.red).accessibilityIdentifier("backup.error")
            }
        } header: {
            Text("Backup", tableName: "PdfIO")
        } footer: {
            Text("Once a day, when something changed, Sheafnote saves a backup file to the folder you choose. It only removes older backup files it made itself, beyond the number you keep.", tableName: "PdfIO")
        }
        .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url):
                do { try controller.chooseFolder(url) } catch { errorMessage = error.localizedDescription }
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: Transfer

    private var transferSection: some View {
        Section {
            Button { showLibraryExport = true } label: {
                Label { Text("Export Whole Library…", tableName: "PdfIO") } icon: { Image(systemName: "square.and.arrow.up") }
            }
            .accessibilityIdentifier("backup.exportLibrary")
            Button { showRestorePicker = true } label: {
                Label { Text("Import Backup…", tableName: "PdfIO") } icon: { Image(systemName: "square.and.arrow.down") }
            }
            .disabled(isRestoring)
            .accessibilityIdentifier("backup.import")
        } header: {
            Text("Backup files", tableName: "PdfIO")
        } footer: {
            Text("A .sheafnote file holds your notebooks, writing and attachments. Importing adds them as new copies and never changes what you already have.", tableName: "PdfIO")
        }
        .fileImporter(isPresented: $showRestorePicker, allowedContentTypes: [ImportActions.archiveType]) { result in
            switch result {
            case .success(let url): restore(url)
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
    }

    private func restore(_ url: URL) {
        isRestoring = true
        Task { @MainActor in
            defer { isRestoring = false }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                restoreResult = RestoreResult(summary: try await ArchiveRestore.run(url: url, folderID: nil, services: services))
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct RestoreResult: Identifiable {
    let id = UUID()
    let summary: ArchiveImportSummary
}

/// Exports every notebook as one `.sheafnote` file and offers it to the share sheet.
struct LibraryExportSheet: View {
    let services: AppServices
    @State private var phase = Phase.working(0)
    @State private var task: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss

    enum Phase { case working(Double), ready(URL, ArchiveManifest), failed(String) }

    var body: some View {
        NavigationStack {
            Form {
                switch phase {
                case .working(let fraction):
                    ProgressView(value: fraction) { Text("Packing your library…", tableName: "PdfIO") }
                case .ready(let url, let manifest):
                    Label { Text("Backup file ready", tableName: "PdfIO") } icon: { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                        .accessibilityIdentifier("libraryExport.ready")
                    LabeledContent { Text(manifest.counts.notebooks, format: .number) } label: { Text("Notebooks", tableName: "PdfIO") }
                    LabeledContent { Text(manifest.counts.pages, format: .number) } label: { Text("Pages", tableName: "PdfIO") }
                    ShareLink(item: url) { Label { Text("Share or Save…", tableName: "PdfIO") } icon: { Image(systemName: "square.and.arrow.up") } }
                case .failed(let message):
                    Label { Text(message) } icon: { Image(systemName: "exclamationmark.triangle") }.foregroundStyle(.red)
                }
            }
            .navigationTitle(Text("Export Library", tableName: "PdfIO"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Text("Done", tableName: "PdfIO") } } }
            .task { start() }
            .onDisappear { finish() }
        }
    }

    private func start() {
        guard task == nil else { return }
        let url = FileManager.default.temporaryDirectory.appending(path: "\(ExportFolder.prefix)\(UUID().uuidString)")
        task = Task { @MainActor in
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                let file = url.appending(path: "Sheafnote Library \(Date.now.formatted(.iso8601.year().month().day())).\(BackupPolicy.fileExtension)")
                let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1"
                let manifest = try await ArchiveExporter(context: services.context, appVersion: version)
                    .export(.library, to: file) { phase = .working($0) }
                phase = .ready(file, manifest)
            } catch is CancellationError {
                return
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func finish() {
        task?.cancel()
        if case .ready(let file, _) = phase {
            // Best-effort cleanup of our own temporary folder; a leftover is swept by `ExportFolder.removeStale`.
            try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
        }
    }
}
