import Foundation
import Observation

/// Opens the store and builds the feature host once per process; every window shares it.
@MainActor @Observable
final class AppBootstrap {
    enum State {
        case ready(FeatureHost)
        case failed(String)
    }

    static let shared = AppBootstrap()

    let state: State

    private init() {
        do {
            let services = UITestSeed.isActive ? try UITestSeed.makeServices() : try AppServices.live()
            let host = FeatureHost(services: services)
            host.bootstrap()
            state = .ready(host)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
