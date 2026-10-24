import Foundation
import Observation
import OSLog
import SheafnoteCore

/// Reads the handwriting on changed pages in the background and stores the text on the page (so it syncs and the
/// other device skips the page). One page at a time, newest first, only pages that stopped changing, all on-device.
@MainActor @Observable
final class OCRIndexer {
    private static let log = Logger(subsystem: "co.xanom.sheafnote", category: "search.ocr")
    private static let batchSize = 20
    private static let maxPasses = 500
    private static let pauseBetweenPages = Duration.milliseconds(150)

    /// Pages waiting for OCR right now (for Settings).
    private(set) var pendingCount = 0
    private(set) var failedCount = 0
    private(set) var isRunning = false

    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private let store: PageTextStore
    @ObservationIgnored private var failed = Set<String>()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var rerun = false
    @ObservationIgnored private var forced = false

    init(services: AppServices) {
        self.services = services
        self.store = PageTextStore(context: services.context)
    }

    /// Starts a pass unless one is running (then it runs once more when it ends). `force` is for passes the user
    /// asked for: it runs in Low Power Mode and does not wait for recently edited pages to settle.
    func start(force: Bool = false) {
        guard force || !ProcessInfo.processInfo.isLowPowerModeEnabled else { return }
        guard task == nil else { rerun = true; forced = forced || force; return }
        forced = force
        task = Task { [weak self] in
            await self?.runPasses()
            self?.task = nil
            if let self, self.rerun {
                self.rerun = false
                self.start(force: self.forced)
            }
        }
    }

    /// Pages whose handwriting has not been read yet, regardless of how recently they were edited.
    func countPending() -> Int {
        do {
            return OCRSchedulingPolicy.plan(try store.ocrStates(), now: .distantFuture, limit: .max).count
        } catch {
            Self.log.error("Could not count unread pages: \(error.localizedDescription, privacy: .public)")
            return 0
        }
    }

    /// Returns when the current pass (and any pass queued behind it) has finished.
    func waitUntilIdle() async {
        while let running = task { await running.value }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    /// Forgets failures so unreadable pages are tried again.
    func resetFailures() {
        failed.removeAll()
        failedCount = 0
    }

    private func runPasses() async {
        isRunning = true
        defer { isRunning = false }
        for _ in 0..<Self.maxPasses {
            if Task.isCancelled { return }
            let plan = makePlan()
            pendingCount = plan.pending
            guard !plan.items.isEmpty else { return }
            for item in plan.items {
                if Task.isCancelled { return }
                await process(item)
                try? await Task.sleep(for: Self.pauseBetweenPages)
            }
        }
    }

    private func makePlan() -> (items: [OCRPlanItem], pending: Int) {
        do {
            let states = try store.ocrStates()
            let all = OCRSchedulingPolicy.plan(states, now: forced ? .distantFuture : .now, limit: .max)
            let todo = all.filter { !failed.contains(key($0)) }
            return (Array(todo.prefix(Self.batchSize)), todo.count)
        } catch {
            Self.log.error("Could not list pages for OCR: \(error.localizedDescription, privacy: .public)")
            return ([], 0)
        }
    }

    private func process(_ item: OCRPlanItem) async {
        do {
            switch item.action {
            case .clearText:
                try store.clearText(forInkHash: item.inkHash, pageID: item.pageID)
            case .recognize:
                let text = try await recognize(pageID: item.pageID)
                try store.store(text: text, forInkHash: item.inkHash, pageID: item.pageID)
            case .skip:
                break
            }
        } catch is CancellationError {
            return
        } catch {
            failed.insert(key(item))
            failedCount = failed.count
            Self.log.error("OCR failed for a page: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func recognize(pageID: UUID) async throws -> String {
        let options = RenderOptions(includeBackground: false, includeInk: true, includeElements: false,
                                    forExport: false, hideTape: true)
        let image = try await services.pageRenderer.renderImage(pageID: pageID, rect: nil, scale: 2, options: options)
        let languages = SearchPreferences(settings: services.settings).languages
        let result = try await services.recognizer.recognizeText(in: image, languages: languages)
        return result.fullText
    }

    private func key(_ item: OCRPlanItem) -> String { "\(item.pageID.uuidString)|\(item.inkHash)" }
}
