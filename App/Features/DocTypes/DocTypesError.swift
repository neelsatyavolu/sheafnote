import Foundation

/// Errors shown to the person using the app. Every message says what happened and that nothing was lost.
enum DocTypesError: LocalizedError {
    case createFailed(String)
    case saveFailed(String)
    case imageUnreadable

    var errorDescription: String? {
        switch self {
        case .createFailed(let detail):
            String(localized: "Couldn't create the document: \(detail)", table: "DocTypes")
        case .saveFailed(let detail):
            String(localized: "Couldn't save your changes: \(detail)", table: "DocTypes")
        case .imageUnreadable:
            String(localized: "That picture couldn't be read, so it wasn't added. Your text is unchanged.", table: "DocTypes")
        }
    }
}
