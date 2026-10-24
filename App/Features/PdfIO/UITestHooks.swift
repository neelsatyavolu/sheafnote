import Foundation
import OSLog
import SheafnoteCore

/// UI tests cannot drive the system file picker, so in UI-test mode only, `-PdfIOImportFixture <path>` imports a PDF
/// from that path at launch through the same importer the Files picker uses.
@MainActor
enum UITestHooks {
    private static let log = Logger(subsystem: "co.xanom.sheafnote", category: "pdf-io-uitest")

    static func installIfNeeded(into host: FeatureHost) {
        guard UITestSeed.isActive, let path = UserDefaults.standard.string(forKey: "PdfIOImportFixture") else { return }
        let services = host.services
        Task { @MainActor in
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                let importer = PdfImporter(context: services.context, pages: services.pages)
                _ = try await importer.importPDF(data, title: "Imported Fixture", into: nil)
            } catch {
                log.error("Fixture import failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
