import Foundation

/// Apple Pencil double-tap and squeeze. The active tool gets the first chance; otherwise the user's setting decides.
extension NotebookSession {
    func handlePencil(_ action: PencilAction) {
        if let tool = activeTool, tool.handlePencilAction(action, in: self) { return }
        let setting = action == .doubleTap ? prefs.values.doubleTap : prefs.values.squeeze
        perform(setting)
    }

    func perform(_ setting: PencilTapAction) {
        switch setting {
        case .switchToEraser:
            if toolState.activeToolID == .eraser {
                toolState.select(toolState.previousToolID == .eraser ? .pen : toolState.previousToolID)
            } else {
                toolState.select(.eraser)
            }
        case .switchToPrevious:
            toolState.select(toolState.previousToolID)
        case .showPalette:
            paletteRequest += 1
        case .off:
            break
        }
    }
}
