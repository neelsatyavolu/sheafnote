import Observation
import SwiftUI
import SheafnoteCore

enum ExportPageChoice: Hashable {
    case whole, current, selected, range
}

/// State of the export sheet. Owns the running task and the temporary files it produced.
@MainActor @Observable
final class ExportModel {
    enum Phase {
        case idle
        case working(Double)
        case ready(ExportOutput)
        case failed(String)
    }

    let services: AppServices
    let notebooks: [Notebook]
    let currentPageID: UUID?
    let selectedPageIDs: Set<UUID>
    let pageCount: Int

    var kind: ExportKind
    var pageChoice: ExportPageChoice
    var rangeText = ""
    var includeBackground = true
    var imageScale: CGFloat = 2
    private(set) var phase = Phase.idle
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var isDismissed = false

    init(services: AppServices, notebooks: [Notebook], currentPageID: UUID? = nil, selectedPageIDs: Set<UUID> = []) {
        self.services = services
        self.notebooks = notebooks
        self.currentPageID = currentPageID
        self.selectedPageIDs = selectedPageIDs
        self.pageCount = notebooks.count == 1 ? ((try? services.pages.orderedPages(of: notebooks[0].id).count) ?? 0) : 0
        self.pageChoice = selectedPageIDs.isEmpty ? .whole : .selected
        self.kind = notebooks.allSatisfy { $0.kind != .text } ? .pdf : .archive
    }

    // MARK: Available options

    var isSingleNotebook: Bool { notebooks.count == 1 }
    var hasTextDocument: Bool { notebooks.contains { $0.kind == .text } }
    var availableKinds: [ExportKind] {
        if hasTextDocument { return [.archive] }
        return isSingleNotebook ? ExportKind.allCases : [.pdf, .archive]
    }
    var availablePageChoices: [ExportPageChoice] {
        guard isSingleNotebook, kind != .archive else { return [.whole] }
        var choices: [ExportPageChoice] = [.whole]
        if currentPageID != nil { choices.append(.current) }
        if !selectedPageIDs.isEmpty { choices.append(.selected) }
        choices.append(.range)
        return choices
    }
    var usesImages: Bool { kind == .png || kind == .jpeg }
    var supportsBackgroundOption: Bool { kind != .archive }
    var isWorking: Bool { if case .working = phase { true } else { false } }

    /// nil when the typed range isn't valid for this notebook.
    var parsedRange: [Int]? { PageRangeParser.parse(rangeText, pageCount: pageCount) }
    var canStart: Bool {
        guard !isWorking else { return false }
        return !(pageChoice == .range && kind != .archive && parsedRange == nil)
    }

    var scope: ExportScope {
        guard kind != .archive else { return .wholeNotebook }
        switch pageChoice {
        case .whole: return .wholeNotebook
        case .current: return currentPageID.map { .pages([$0]) } ?? .wholeNotebook
        case .selected: return .pages(selectedPageIDs)
        case .range: return .numbers(parsedRange ?? [])
        }
    }

    // MARK: Running

    func start() {
        guard canStart else { return }
        discardOutput()
        phase = .working(0)
        let request = ExportRequest(notebooks: notebooks, scope: scope, kind: kind, includeBackground: includeBackground, imageScale: imageScale)
        let runner = ExportRunner(services: services)
        task = Task { @MainActor [weak self] in
            do {
                let output = try await runner.run(request) { self?.phase = .working($0) }
                guard let self, !isDismissed else {
                    try? FileManager.default.removeItem(at: output.directory)   // best-effort cleanup of our own temp folder
                    return
                }
                phase = .ready(output)
            } catch is CancellationError {
                self?.phase = .idle
            } catch {
                self?.phase = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        task?.cancel()
    }

    /// The sheet is going away: stop any run and delete what it made.
    func dismiss() {
        isDismissed = true
        task?.cancel()
        discardOutput()
    }

    /// Deletes the temporary files. Called when the sheet goes away or a new run starts.
    func discardOutput() {
        // Best-effort cleanup of our own temporary folder; a leftover is swept by `ExportFolder.removeStale`.
        if case .ready(let output) = phase { try? FileManager.default.removeItem(at: output.directory) }
        phase = .idle
    }
}
