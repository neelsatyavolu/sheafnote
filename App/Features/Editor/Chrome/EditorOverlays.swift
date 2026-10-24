import SwiftUI
import SheafnoteCore

/// Floating pieces over the canvas: page indicator, toast, save-failure and unreadable-page banners.
struct EditorOverlays: View {
    let session: NotebookSession
    @Binding var showGoTo: Bool

    var body: some View {
        VStack(spacing: 8) {
            if let failure = session.saveFailure { banner(failure, symbol: "exclamationmark.triangle.fill") }
            if let problem = session.currentPageProblem { banner(problem, symbol: "lock.doc") }
            if let toast = session.toast {
                Text(toast.message)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .glassEffect(.regular, in: Capsule())
                    .transition(.opacity)
                    .task(id: toast.id) {
                        do { try await Task.sleep(for: .seconds(2.2)) } catch { return }
                        if session.toast?.id == toast.id { session.toast = nil }
                    }
                    .accessibilityAddTraits(.updatesFrequently)
            }
            Spacer()
            pageIndicator
        }
        .padding(.top, 8)
        .padding(.bottom, 12)
        .allowsHitTesting(true)
    }

    @ViewBuilder
    private var pageIndicator: some View {
        if session.pageIDs.count > 1 {
            Button { showGoTo = true } label: {
                Text("\(session.currentPageNumber) / \(session.pageIDs.count)")
                    .font(.footnote.monospacedDigit().weight(.medium))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .glassEffect(.regular, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Page \(session.currentPageNumber) of \(session.pageIDs.count)", tableName: "Editor"))
            .accessibilityHint(Text("Double tap to go to a page", tableName: "Editor"))
            .accessibilityIdentifier("editor.pageIndicator")
        }
    }

    private func banner(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.footnote)
            .padding(12)
            .frame(maxWidth: 560, alignment: .leading)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 16)
            .accessibilityIdentifier("editor.banner")
    }
}

extension NotebookSession {
    /// Message when the page in view could not be decoded and is therefore read-only.
    var currentPageProblem: String? {
        currentPageID.flatMap { pageSessions[$0]?.loadProblem }
    }
}
