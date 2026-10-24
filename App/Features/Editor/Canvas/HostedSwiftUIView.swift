import SwiftUI
import UIKit

/// A UIView that shows SwiftUI content. The hosting controller is attached as a child of the nearest view controller
/// once the view is in a window, so SwiftUI gets proper lifecycle and trait propagation.
@MainActor
class HostedSwiftUIView<Content: View>: UIView {
    private let controller: UIHostingController<Content>

    init(rootView: Content) {
        controller = UIHostingController(rootView: rootView)
        super.init(frame: .zero)
        backgroundColor = .clear
        controller.view.backgroundColor = .clear
        controller.safeAreaRegions = []
        controller.view.frame = bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(controller.view)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var hostedView: UIView { controller.view }

    func update(rootView: Content) { controller.rootView = rootView }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            guard controller.parent != nil else { return }
            controller.willMove(toParent: nil)
            controller.removeFromParent()
        } else if controller.parent == nil, let parent = nearestViewController {
            parent.addChild(controller)
            controller.didMove(toParent: parent)
        }
    }

    private var nearestViewController: UIViewController? {
        var responder: UIResponder? = self
        while let next = responder?.next {
            if let controller = next as? UIViewController { return controller }
            responder = next
        }
        return nil
    }
}
