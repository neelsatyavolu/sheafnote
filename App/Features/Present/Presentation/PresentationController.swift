import Observation
import SwiftUI
import SheafnoteCore

/// Owns the presentation: which notebook is presented, where (external display or this device), and the options.
/// The state machine decides; this class turns decisions into scenes and views.
@MainActor @Observable
final class PresentationController {
    static let shared = PresentationController()

    private(set) var machine: PresentationStateMachine
    let mirror = PageMirror()
    private(set) var notebookID: UUID?
    private(set) var notice: String?

    @ObservationIgnored private weak var editor: (any EditorContext)?
    @ObservationIgnored private var externalSceneIDs: Set<String> = []

    private static let optionsKey = "present.options"

    init() {
        let stored = UserDefaults.standard.data(forKey: Self.optionsKey)
            .flatMap { try? JSONDecoder().decode(PresentationOptions.self, from: $0) }
        machine = PresentationStateMachine(options: stored ?? PresentationOptions())
    }

    var options: PresentationOptions {
        get { machine.options }
        set {
            machine.options = newValue
            persistOptions()
            reconcile()
        }
    }

    var isPresenting: Bool { machine.isPresenting }
    var hasExternalDisplay: Bool { machine.externalDisplayCount > 0 }
    var currentEditor: (any EditorContext)? { editor }
    var laser: LaserController? { notebookID.map { LaserController.controller(for: $0) } }
    var zoom: ZoomWindowController? { notebookID.flatMap { ZoomWindowController.existing(for: $0) } }

    // MARK: Start and stop

    func start(editor: EditorContext) {
        self.editor = editor
        notebookID = editor.notebook.id
        notice = nil
        machine.start()
        reconcile()
    }

    func stop() {
        machine.stop()
        reconcile()
    }

    // MARK: External displays

    func displayConnected(sceneID: String) {
        guard externalSceneIDs.insert(sceneID).inserted else { return }
        machine.displayConnected()
        reconcile()
    }

    func displayDisconnected(sceneID: String) {
        guard externalSceneIDs.remove(sceneID) != nil else { return }
        let wasExternal = machine.mode == .external
        machine.displayDisconnected()
        if wasExternal, machine.mode == .idle {
            notice = String(localized: "The display was disconnected, so presenting stopped.", table: "Present")
        }
        reconcile()
    }

    // MARK: Reconciling views with the state machine

    private func reconcile() {
        guard machine.isPresenting, let editor else {
            mirror.stop()
            DevicePresenter.shared.dismiss()
            if !machine.isPresenting {
                notebookID = nil
                editor = nil
            }
            return
        }
        if !mirror.isRunning {
            mirror.start(editor: editor) { [weak self] in self?.stop() }
        }
        if machine.showsDevicePresenter {
            DevicePresenter.shared.present(controller: self)
        } else {
            DevicePresenter.shared.dismiss()
        }
    }

    private func persistOptions() {
        do {
            UserDefaults.standard.set(try JSONEncoder().encode(machine.options), forKey: Self.optionsKey)
        } catch {
            notice = error.localizedDescription
        }
    }

    func clearNotice() { notice = nil }
}
