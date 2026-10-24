import Foundation
import Observation
import OSLog
import SheafnoteCore

/// The app-wide search index: built from the library, kept current as notes change, queried by the library and
/// in-notebook search screens. Handwriting text comes from `OCRIndexer`; PDF text is read here, on this device.
@MainActor @Observable
final class SearchService {
    private static let log = Logger(subsystem: "co.xanom.sheafnote", category: "search")
    /// Quiet time after the last change before the index is refreshed.
    private static let refreshDelay = Duration.seconds(1.5)
    /// Quiet time before handwriting is read; longer than `OCRSchedulingPolicy.settleInterval`.
    private static let ocrDelay = Duration.seconds(5)

    /// Set by `SearchFeature.register`.
    static var shared: SearchService?

    /// Bumped after every index refresh so open search screens re-run their query.
    private(set) var revision = 0
    @ObservationIgnored let ocr: OCRIndexer
    @ObservationIgnored let services: AppServices
    @ObservationIgnored private(set) var index = SearchIndex()
    @ObservationIgnored private let corpus: SearchCorpus
    @ObservationIgnored private var pdfTexts: PDFTextCache = [:]
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var ocrTask: Task<Void, Never>?
    @ObservationIgnored private var isLoadingPDFs = false

    init(services: AppServices) {
        self.services = services
        self.corpus = SearchCorpus(context: services.context)
        self.ocr = OCRIndexer(services: services)
    }

    /// Refreshes after any library change, and reads new handwriting once the user has paused.
    func startObserving() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: .sheafnoteModelDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.libraryDidChange() }
        }
    }

    private func libraryDidChange() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: Self.refreshDelay)
            guard !Task.isCancelled else { return }
            await self?.refreshIndex()
        }
        ocrTask?.cancel()
        ocrTask = Task { [weak self] in
            try? await Task.sleep(for: Self.ocrDelay)
            guard !Task.isCancelled else { return }
            self?.ocr.start()
        }
    }

    // MARK: Index

    /// Brings the index up to date with the library. Cheap when nothing changed.
    func refreshIndex() async {
        refreshNow()
        await loadPDFTextsIfNeeded()
    }

    private func refreshNow() {
        do {
            let report = try corpus.refresh(&index, pdfTexts: pdfTexts)
            if report.updated + report.removed > 0 { revision += 1 }
        } catch {
            Self.log.error("Index refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Foreground and launch work: refresh the index and read any unread handwriting. Returns at once.
    func kickOff(force: Bool = false) {
        Task { [weak self] in await self?.refreshIndex() }
        ocr.start(force: force)
    }

    func search(_ query: String, notebookID: UUID? = nil) -> [SearchHit] {
        index.search(query, notebookID: notebookID)
    }

    /// Settings, "Rebuild Search Index": every page is read again. Ink and existing text stay until replaced.
    func rebuild() throws {
        ocr.cancel()
        ocr.resetFailures()
        _ = try PageTextStore(context: services.context).invalidateAll()
        pdfTexts.removeAll()
        kickOff(force: true)
    }

    // MARK: PDF text

    private func loadPDFTextsIfNeeded() async {
        guard !isLoadingPDFs else { return }
        isLoadingPDFs = true
        defer { isLoadingPDFs = false }
        let missing: Set<UUID>
        do { missing = try corpus.missingPDFAssets(cache: pdfTexts) } catch {
            Self.log.error("PDF list failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        guard !missing.isEmpty else { return }
        for assetID in missing {
            pdfTexts[assetID] = await extractText(of: assetID)
        }
        refreshNow()
    }

    /// An asset that is not a readable PDF (for example an imported image) simply has no text.
    private func extractText(of assetID: UUID) async -> [String] {
        guard let data = try? await services.pages.data(for: assetID) else { return [] }
        let result = await Task.detached(priority: .utility) { Result { try PDFTextExtractor.pageTexts(from: data) } }.value
        switch result {
        case .success(let texts): return texts
        case .failure(let error):
            Self.log.info("No searchable text in an attached file: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}
