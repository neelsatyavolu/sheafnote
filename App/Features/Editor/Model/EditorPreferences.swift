import Foundation
import Observation
import SheafnoteCore

enum PencilTapAction: String, Codable, CaseIterable, Sendable {
    case switchToEraser, switchToPrevious, showPalette, off
}

enum EraserMode: String, Codable, CaseIterable, Sendable {
    /// Removes whole strokes.
    case stroke
    /// Erases only the part under the eraser (PencilKit bitmap eraser).
    case partial
}

struct EditorPreferenceValues: Codable, Equatable, Sendable {
    var inputMode: String = InputMode.anyInput.rawValue
    var doubleTap: PencilTapAction = .switchToEraser
    var squeeze: PencilTapAction = .showPalette
    var eraserMode: EraserMode = .stroke
    var eraserHighlighterOnly = false
    var eraserSwitchBack = false
}

/// Device-local editor settings (Pencil gestures, input mode, eraser options). One instance per app launch.
@MainActor @Observable
final class EditorPreferences {
    private static let key = "editor.preferences"

    private let settings: AppSettingsStore
    var values: EditorPreferenceValues {
        didSet { if values != oldValue { settings.setLocal(values, for: Self.key) } }
    }

    init(settings: AppSettingsStore) {
        self.settings = settings
        self.values = settings.local(Self.key, as: EditorPreferenceValues.self) ?? EditorPreferenceValues()
    }

    var inputMode: InputMode {
        get { InputMode(rawValue: values.inputMode) ?? .anyInput }
        set { values.inputMode = newValue.rawValue }
    }

    /// Set once by `EditorFeature.register`; the settings section and every notebook session share it.
    static var shared: EditorPreferences?
}
