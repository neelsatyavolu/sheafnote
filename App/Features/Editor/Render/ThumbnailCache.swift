import CoreGraphics
import Foundation
import ImageIO
import OSLog
import UniformTypeIdentifiers

/// Page thumbnails: a memory cache in front of PNG files in the Caches folder (the system may purge them; they are
/// always re-rendered from the page). Keys include a content signature, so a changed page never shows an old thumbnail.
@MainActor
final class ThumbnailCache {
    private static let log = Logger(subsystem: "co.xanom.sheafnote", category: "thumbnails")
    private let memory = NSCache<NSString, CGImage>()
    private let directory: URL

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SheafnoteThumbnails", isDirectory: true)
        self.directory = base
        memory.countLimit = 200
        do {
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        } catch {
            Self.log.error("Could not create thumbnail cache: \(error.localizedDescription, privacy: .public)")
        }
    }

    func image(for key: String) -> CGImage? {
        if let hit = memory.object(forKey: key as NSString) { return hit }
        let url = fileURL(key)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        memory.setObject(image, forKey: key as NSString)
        return image
    }

    func store(_ image: CGImage, for key: String) {
        memory.setObject(image, forKey: key as NSString)
        let url = fileURL(key)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        if !CGImageDestinationFinalize(destination) {
            Self.log.error("Could not write thumbnail \(key, privacy: .public)")
        }
    }

    private func fileURL(_ key: String) -> URL { directory.appendingPathComponent("\(key).png") }
}
