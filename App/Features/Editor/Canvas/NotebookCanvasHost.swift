import SwiftUI

/// SwiftUI entry point for the notebook's zoomable page canvas.
struct NotebookCanvasHost: UIViewControllerRepresentable {
    let session: NotebookSession

    func makeUIViewController(context: Context) -> NotebookScrollController {
        NotebookScrollController(session: session)
    }

    func updateUIViewController(_ controller: NotebookScrollController, context: Context) {}
}
