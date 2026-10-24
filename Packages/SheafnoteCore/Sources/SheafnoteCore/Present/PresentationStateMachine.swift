import Foundation

public struct PresentationOptions: Codable, Equatable, Sendable {
    /// Cover the editor on the device with a clean presenter view while presenting.
    public var hideToolbars: Bool
    public var showLaser: Bool
    public var showZoomWindow: Bool

    public init(hideToolbars: Bool = true, showLaser: Bool = true, showZoomWindow: Bool = true) {
        self.hideToolbars = hideToolbars
        self.showLaser = showLaser
        self.showZoomWindow = showZoomWindow
    }
}

public enum PresentationMode: Equatable, Sendable {
    case idle
    /// Mirroring the page to an external display or AirPlay.
    case external
    /// No display is connected: the page fills this device's screen.
    case onDevice
}

/// What is presented where, as displays come and go. Pure logic; the app turns it into scenes and views.
public struct PresentationStateMachine: Equatable, Sendable {
    public private(set) var mode: PresentationMode = .idle
    public private(set) var externalDisplayCount = 0
    public var options: PresentationOptions

    public init(options: PresentationOptions = PresentationOptions()) {
        self.options = options
    }

    public var isPresenting: Bool { mode != .idle }

    /// The device shows a clean full-screen presenter instead of the editor.
    public var showsDevicePresenter: Bool {
        switch mode {
        case .idle: false
        case .onDevice: true
        case .external: options.hideToolbars
        }
    }

    public var externalShowsPage: Bool { mode == .external }
    public var externalShowsLaser: Bool { externalShowsPage && options.showLaser }
    public var externalShowsZoomWindow: Bool { externalShowsPage && options.showZoomWindow }

    public mutating func start() {
        guard mode == .idle else { return }
        mode = externalDisplayCount > 0 ? .external : .onDevice
    }

    public mutating func stop() { mode = .idle }

    public mutating func displayConnected() {
        externalDisplayCount += 1
        if mode == .onDevice { mode = .external }
    }

    /// Unplugging the last display ends external presenting rather than silently switching the audience's view.
    public mutating func displayDisconnected() {
        externalDisplayCount = max(0, externalDisplayCount - 1)
        if mode == .external, externalDisplayCount == 0 { mode = .idle }
    }
}
