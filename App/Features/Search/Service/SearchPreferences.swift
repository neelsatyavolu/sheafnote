import Foundation
import Vision
import SheafnoteCore

/// Device-local search settings (handwriting languages).
@MainActor
struct SearchPreferences {
    private static let languagesKey = "search.languages"
    let settings: AppSettingsStore

    /// Empty means automatic, with English first.
    var languages: [String] {
        get { settings.local(Self.languagesKey, as: [String].self) ?? [] }
        nonmutating set { settings.setLocal(newValue, for: Self.languagesKey) }
    }

    /// Languages Vision can read with the accurate recognizer on this OS.
    static func supportedLanguages() -> [String] {
        (try? VNRecognizeTextRequest().supportedRecognitionLanguages()) ?? ["en-US"]
    }
}
