import SwiftUI

/// SwiftUI entry point for the notebook's zoomable page canvas.
struct NotebookCanvasHost: UIViewControllerRepresentable {
    let session: NotebookSession
    var fold: CGRect?

    func makeUIViewController(context: Context) -> NotebookScrollController {
        NotebookScrollController(session: session)
    }

    func updateUIViewController(_ controller: NotebookScrollController, context: Context) {
        controller.fold = fold
    }
}
