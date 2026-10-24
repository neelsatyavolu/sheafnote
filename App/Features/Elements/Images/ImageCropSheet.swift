import SwiftUI
import SheafnoteCore

/// Opens the crop editor for an image element and writes the result as one undoable edit.
@MainActor
enum ImageCropPresenter {
    static func present(_ element: ElementValue, page: any PageContext, editor: EditorContext,
                        cache: ElementImageCache, host: FeatureHost) {
        guard element.kind == .image, let assetID = element.assetID,
              let payload = element.decoded(ImagePayload.self) else { return }
        let elementID = element.id
        editor.present(EditorSheet(detents: [.large]) {
            AnyView(ImageCropSheet(assetID: assetID, cache: cache, initialCrop: ImageCropMath.clamped(payload.cropRect)) { crop in
                apply(crop, to: elementID, page: page, editor: editor, host: host)
            })
        })
    }

    private static func apply(_ crop: CGRect, to id: UUID, page: any PageContext, editor: EditorContext, host: FeatureHost) {
        guard let element = page.elements.all.first(where: { $0.id == id }),
              let payload = element.decoded(ImagePayload.self) else { return }
        let old = ImageCropMath.clamped(payload.cropRect)
        let new = ImageCropMath.clamped(crop)
        guard old != new else { return }
        var updated = payload
        updated.cropRect = new
        let frame = ImageCropMath.frame(after: new, from: old, frame: element.frame, rotation: element.rotation)
        do {
            try page.elements.update(id: id, undoName: LocalizedStringResource("Crop Image", table: "Elements")) {
                $0.payload = PayloadCodec.encode(updated)
                $0.frame = frame
            }
            ElementSelecting.refreshSelection(for: id, on: page, editor: editor, host: host)
        } catch {
            ElementErrors.report(error, editor: editor)
        }
    }
}

/// Drag the frame to move it, drag a corner to resize. The picture itself is never changed.
struct ImageCropSheet: View {
    let assetID: UUID
    let cache: ElementImageCache
    let initialCrop: CGRect
    let onApply: (CGRect) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var crop: CGRect
    @State private var dragStart: CGRect?

    init(assetID: UUID, cache: ElementImageCache, initialCrop: CGRect, onApply: @escaping (CGRect) -> Void) {
        self.assetID = assetID
        self.cache = cache
        self.initialCrop = initialCrop
        self.onApply = onApply
        _crop = State(initialValue: initialCrop)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let image { cropper(image) } else { ProgressView() }
            }
            .padding()
            .navigationTitle(Text("Crop Image", tableName: "Elements"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel", tableName: "Elements") }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button { crop = CGRect(x: 0, y: 0, width: 1, height: 1) } label: { Text("Reset", tableName: "Elements") }
                        .accessibilityIdentifier("elements.crop.reset")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { onApply(crop); dismiss() } label: { Text("Done", tableName: "Elements") }
                        .accessibilityIdentifier("elements.crop.done")
                }
            }
        }
        .task { image = await cache.image(for: assetID) }
    }

    private func cropper(_ image: UIImage) -> some View {
        GeometryReader { geo in
            let fit = fitRect(for: image.size, in: geo.size)
            ZStack(alignment: .topLeading) {
                Image(uiImage: image).resizable().frame(width: fit.width, height: fit.height)
                    .position(x: fit.midX, y: fit.midY)
                    .accessibilityHidden(true)
                dimming(fit: fit)
                cropFrame(fit: fit)
            }
            .coordinateSpace(name: "elements.crop.space")
        }
    }

    private func fitRect(for size: CGSize, in container: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        let scale = min(container.width / size.width, container.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(x: (container.width - fitted.width) / 2, y: (container.height - fitted.height) / 2,
                      width: fitted.width, height: fitted.height)
    }

    private func screenRect(_ unit: CGRect, fit: CGRect) -> CGRect {
        CGRect(x: fit.minX + unit.minX * fit.width, y: fit.minY + unit.minY * fit.height,
               width: unit.width * fit.width, height: unit.height * fit.height)
    }

    private func dimming(fit: CGRect) -> some View {
        Path { p in
            p.addRect(fit)
            p.addRect(screenRect(crop, fit: fit))
        }
        .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))
        .allowsHitTesting(false)
    }

    private func cropFrame(fit: CGRect) -> some View {
        let rect = screenRect(crop, fit: fit)
        return ZStack {
            Rectangle().strokeBorder(Color.white, lineWidth: 2)
            Rectangle().fill(Color.white.opacity(0.001))
                .gesture(moveGesture(fit: fit))
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
        .overlay {
            ForEach(0..<4, id: \.self) { corner in handle(corner, rect: rect, fit: fit) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Crop area", tableName: "Elements"))
    }

    private func handle(_ corner: Int, rect: CGRect, fit: CGRect) -> some View {
        let point = CGPoint(x: corner % 2 == 0 ? rect.minX : rect.maxX, y: corner < 2 ? rect.minY : rect.maxY)
        return Circle().fill(Color.white).overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
            .frame(width: 26, height: 26)
            .contentShape(Circle().inset(by: -10))
            .position(point)
            .gesture(cornerGesture(corner, fit: fit))
            .accessibilityLabel(Text("Crop handle", tableName: "Elements"))
    }

    private func moveGesture(fit: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let start = dragStart ?? crop
                dragStart = start
                let dx = value.translation.width / fit.width, dy = value.translation.height / fit.height
                crop = ImageCropMath.clamped(start.offsetBy(dx: dx, dy: dy))
            }
            .onEnded { _ in dragStart = nil }
    }

    private func cornerGesture(_ corner: Int, fit: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named("elements.crop.space"))
            .onChanged { value in
                let start = dragStart ?? crop
                dragStart = start
                let anchor = CGPoint(x: corner % 2 == 0 ? start.maxX : start.minX, y: corner < 2 ? start.maxY : start.minY)
                let moving = CGPoint(x: min(max((value.location.x - fit.minX) / fit.width, 0), 1),
                                     y: min(max((value.location.y - fit.minY) / fit.height, 0), 1))
                crop = ImageCropMath.clamped(CGRect(x: min(anchor.x, moving.x), y: min(anchor.y, moving.y),
                                                    width: abs(anchor.x - moving.x), height: abs(anchor.y - moving.y)))
            }
            .onEnded { _ in dragStart = nil }
    }
}
