import SwiftUI
import SheafnoteCore

/// A small rendered page, for bookmark and link pickers.
struct PageThumbnailView: View {
    let pageID: UUID
    let services: AppServices
    var width: CGFloat = 240

    @State private var image: CGImage?

    var body: some View {
        let size = services.pages.page(id: pageID)?.size ?? CGSize(width: 595, height: 842)
        ZStack {
            Rectangle().fill(Theme.paper)
            if let image { Image(decorative: image, scale: 2).resizable().scaledToFit() }
        }
        .aspectRatio(size.width / max(size.height, 1), contentMode: .fit)
        .shadow(color: Theme.shadowColor, radius: 4, y: 2)
        .task(id: pageID) { image = await services.pageRenderer.thumbnail(pageID: pageID, width: width) }
    }
}
