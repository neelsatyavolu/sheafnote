import Foundation
import Testing
@testable import SheafnoteCore

@Suite("PresentationStateMachine")
struct PresentationStateMachineTests {
    @Test func startsIdle() {
        let machine = PresentationStateMachine()
        #expect(machine.mode == .idle)
        #expect(!machine.isPresenting)
        #expect(!machine.showsDevicePresenter)
    }

    @Test func startWithoutDisplayPresentsOnDevice() {
        var machine = PresentationStateMachine()
        machine.start()
        #expect(machine.mode == .onDevice)
        #expect(machine.showsDevicePresenter)
        #expect(!machine.externalShowsPage)
    }

    @Test func startWithDisplayMirrorsExternally() {
        var machine = PresentationStateMachine()
        machine.displayConnected()
        machine.start()
        #expect(machine.mode == .external)
        #expect(machine.externalShowsPage)
    }

    @Test func hideToolbarsAlsoOpensThePresenterOnTheDevice() {
        var machine = PresentationStateMachine(options: .init(hideToolbars: true, showLaser: true, showZoomWindow: true))
        machine.displayConnected()
        machine.start()
        #expect(machine.showsDevicePresenter)
        machine.options.hideToolbars = false
        #expect(!machine.showsDevicePresenter)
    }

    @Test func connectingADisplayWhilePresentingOnDeviceMovesToExternal() {
        var machine = PresentationStateMachine()
        machine.start()
        machine.displayConnected()
        #expect(machine.mode == .external)
    }

    @Test func unpluggingTheLastDisplayEndsExternalPresenting() {
        var machine = PresentationStateMachine()
        machine.displayConnected()
        machine.displayConnected()
        machine.start()
        machine.displayDisconnected()
        #expect(machine.mode == .external)
        machine.displayDisconnected()
        #expect(machine.mode == .idle)
        machine.displayDisconnected()
        #expect(machine.externalDisplayCount == 0)
    }

    @Test func stopReturnsToIdle() {
        var machine = PresentationStateMachine()
        machine.start()
        machine.stop()
        #expect(machine.mode == .idle)
    }

    @Test func startingTwiceKeepsTheMode() {
        var machine = PresentationStateMachine()
        machine.start()
        machine.start()
        #expect(machine.mode == .onDevice)
    }

    @Test func externalOverlaysFollowOptions() {
        var machine = PresentationStateMachine()
        machine.displayConnected()
        machine.start()
        #expect(machine.externalShowsLaser)
        #expect(machine.externalShowsZoomWindow)
        machine.options.showLaser = false
        machine.options.showZoomWindow = false
        #expect(!machine.externalShowsLaser)
        #expect(!machine.externalShowsZoomWindow)
    }

    @Test func overlaysAreOffWhenNotPresenting() {
        var machine = PresentationStateMachine()
        machine.displayConnected()
        #expect(!machine.externalShowsLaser)
        #expect(!machine.externalShowsPage)
    }

    @Test func optionsRoundTripThroughJSON() throws {
        let options = PresentationOptions(hideToolbars: false, showLaser: true, showZoomWindow: false)
        let data = try JSONEncoder().encode(options)
        #expect(try JSONDecoder().decode(PresentationOptions.self, from: data) == options)
    }
}
