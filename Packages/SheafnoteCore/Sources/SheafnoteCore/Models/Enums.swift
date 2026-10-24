import CoreGraphics
import Foundation

public enum NotebookKind: String, Codable, CaseIterable, Sendable { case paged, whiteboard, text }

public enum ElementKind: String, Codable, CaseIterable, Sendable { case text, image, sticker, tape, link, shape }

public enum AssetKind: String, Codable, CaseIterable, Sendable { case pdf, image, audio, thumbnail }

public enum PageOrientation: String, Codable, CaseIterable, Sendable { case portrait, landscape }

public enum PaperColor: String, Codable, CaseIterable, Sendable { case white, yellow, dark }

public enum ScrollDirection: String, Codable, CaseIterable, Sendable { case vertical, horizontal }

public enum OutlineSource: String, Codable, Sendable { case user, pdf }

/// Page sizes in PDF points (1/72 in), portrait.
public enum PaperSize: String, Codable, CaseIterable, Sendable {
    case a4, letter, a5, square

    public var portraitSize: CGSize {
        switch self {
        case .a4: CGSize(width: 595, height: 842)
        case .letter: CGSize(width: 612, height: 792)
        case .a5: CGSize(width: 420, height: 595)
        case .square: CGSize(width: 600, height: 600)
        }
    }

    public func size(orientation: PageOrientation) -> CGSize {
        let p = portraitSize
        return orientation == .portrait ? p : CGSize(width: p.height, height: p.width)
    }

    /// Nominal physical size in millimetres (portrait).
    public var millimetres: CGSize {
        switch self {
        case .a4: CGSize(width: 210, height: 297)
        case .letter: CGSize(width: 215.9, height: 279.4)
        case .a5: CGSize(width: 148, height: 210)
        case .square: CGSize(width: 211.7, height: 211.7)
        }
    }

    public var supportsOrientation: Bool { self != .square }
}
