import CoreGraphics
import Foundation
import Vision

public struct RecognizedLine: Sendable, Hashable {
    public var text: String
    public var confidence: Float
    /// Normalized, bottom-left origin as Vision returns it.
    public var boundingBox: CGRect

    public init(text: String, confidence: Float, boundingBox: CGRect) {
        self.text = text
        self.confidence = confidence
        self.boundingBox = boundingBox
    }
}

public struct RecognizedText: Sendable, Hashable {
    public var lines: [RecognizedLine]
    public var fullText: String { lines.map(\.text).joined(separator: "\n") }

    public init(lines: [RecognizedLine]) { self.lines = lines }
}

public enum RecognitionError: LocalizedError {
    case cancelled
    case visionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .cancelled: "Text recognition was cancelled."
        case .visionFailed(let reason): "Sheafnote could not read the handwriting: \(reason)"
        }
    }
}

public protocol HandwritingRecognizing: Sendable {
    /// `languages` empty = automatic, English first.
    func recognizeText(in image: CGImage, languages: [String]) async throws -> RecognizedText
}

/// On-device Vision text recognition (`.accurate`). Never touches the network.
public struct VisionHandwritingRecognizer: HandwritingRecognizing {
    public init() {}

    public func recognizeText(in image: CGImage, languages: [String]) async throws -> RecognizedText {
        let box = SendableImage(image)
        return try await Task.detached(priority: .utility) {
            try Self.perform(box.image, languages: languages)
        }.value
    }

    private static func perform(_ image: CGImage, languages: [String]) throws -> RecognizedText {
        if Task.isCancelled { throw RecognitionError.cancelled }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        if languages.isEmpty {
            request.recognitionLanguages = ["en-US"]
            request.automaticallyDetectsLanguage = true
        } else {
            request.recognitionLanguages = languages
        }
        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            throw RecognitionError.visionFailed(error.localizedDescription)
        }
        if Task.isCancelled { throw RecognitionError.cancelled }
        let lines = (request.results ?? []).compactMap { obs -> RecognizedLine? in
            guard let top = obs.topCandidates(1).first else { return nil }
            return RecognizedLine(text: top.string, confidence: top.confidence, boundingBox: obs.boundingBox)
        }
        // Top-to-bottom reading order (Vision boxes are bottom-left origin).
        return RecognizedText(lines: lines.sorted { $0.boundingBox.midY > $1.boundingBox.midY })
    }
}

private struct SendableImage: @unchecked Sendable {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}
