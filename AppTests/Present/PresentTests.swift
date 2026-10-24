import PencilKit
import SwiftUI
import Testing
import UIKit
import SheafnoteCore
@testable import Sheafnote

@MainActor
@Suite struct PresentRegistrationTests {
    @Test func registersLaserZoomMenuAndLibraryAction() throws {
        let services = try AppServices.inMemory()
        let host = FeatureHost(services: services)
        PresentFeature.register(into: host)

        let laser = try #require(host.tools.tool(.laser))
        #expect(laser.inputPolicy == .overlayCapturesAll)
        #expect(laser.supportedKinds.contains(.paged))
        if case .primary = laser.placement {} else { Issue.record("laser should be a primary tool") }

        let zoom = try #require(host.tools.tool(.zoomWindow))
        if case .more = zoom.placement {} else { Issue.record("zoom window should live in the more menu") }

        #expect(host.notebookMenu.menuItems.contains { $0.id == "present" && $0.group == .view })
        #expect(host.notebookMenu.barItems.contains { $0.id == "present.stop" })
        #expect(host.library.notebookActions.contains { $0.id == "present.openInNewWindow" })
    }
}

@MainActor
@Suite struct LaserControllerTests {
    @Test func touchesBuildATrailThatFadesAway() async throws {
        let controller = LaserController()
        let page = UUID()
        controller.touchMoved(on: page, at: CGPoint(x: 10, y: 10), zoomScale: 2)
        controller.touchMoved(on: page, at: CGPoint(x: 30, y: 10), zoomScale: 2)
        #expect(controller.model.head == CGPoint(x: 30, y: 10))
        #expect(controller.isAnimating)
        #expect(controller.pageUnitsPerPoint == 0.5)

        controller.touchEnded()
        #expect(controller.model.head == nil)
        #expect(!controller.model.isEmpty)
        controller.reset()
        #expect(controller.model.isEmpty)
        #expect(!controller.isAnimating)
    }

    @Test func colorStyleAndSizeChangesAreApplied() {
        let defaults = UserDefaults.standard
        let keys = ["present.laser.color", "present.laser.diameter", "present.laser.style"]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer { for (key, value) in zip(keys, saved) { defaults.set(value, forKey: key) } }

        let controller = LaserController()
        controller.setColor("green")
        controller.setStyle(.dot)
        controller.setDiameter(30)
        #expect(controller.colorID == "green")
        #expect(controller.model.style == .dot)
        #expect(controller.diameter == 30)
        #expect(LaserController().colorID == "green", "the choice is remembered")
    }

    @Test func movingToAnotherPageStartsANewTrail() {
        let controller = LaserController()
        let first = UUID(), second = UUID()
        controller.touchMoved(on: first, at: CGPoint(x: 1, y: 1), zoomScale: 1)
        controller.touchMoved(on: second, at: CGPoint(x: 9, y: 9), zoomScale: 1)
        #expect(controller.pageID == second)
        #expect(controller.model.points.count == 1)
        controller.reset()
    }

    @Test func laserToolNeverTouchesInk() throws {
        let fixture = try EditorFixture()
        let tool = LaserTool()
        let page = try fixture.page()
        let before = page.ink.strokes.count
        let controller = LaserController.controller(for: fixture.notebook.id)
        controller.touchMoved(on: page.pageID, at: CGPoint(x: 5, y: 5), zoomScale: 1)
        controller.touchEnded()
        #expect(page.ink.strokes.count == before)
        #expect(tool.makeOverlay(for: page, in: fixture.session) != nil)
        controller.reset()
    }
}

@MainActor
@Suite struct ZoomStrokeBuilderTests {
    private func spec() -> ZoomInkSpec {
        ZoomInkSpec(ink: PKInk(.pen, color: .black), width: 3, color: .black)
    }

    private func samples(_ points: [CGPoint]) -> [StripSample] {
        points.enumerated().map { StripSample(location: $0.element, time: Double($0.offset) * 0.01, azimuth: 0, altitude: .pi / 2) }
    }

    @Test func stripPointsLandInPageCoordinates() throws {
        var model = ZoomWindowModel(pageSize: CGSize(width: 800, height: 1000), magnification: 4, stripAspect: 5)
        model.moveFocus(to: CGPoint(x: 100, y: 300))
        let strip = CGSize(width: 500, height: 100)   // 0.4 page points per strip point
        let stroke = try #require(ZoomStrokeBuilder.build(samples: samples([CGPoint(x: 0, y: 50), CGPoint(x: 250, y: 50)]),
                                                          model: model, stripSize: strip, spec: spec()))
        let first = stroke.path.first!, last = stroke.path.last!
        #expect(abs(first.location.x - 100) < 0.001 && abs(first.location.y - 320) < 0.001)
        #expect(abs(last.location.x - 200) < 0.001)
        #expect(first.size.width == 3)
    }

    @Test func aSingleTapBecomesADot() throws {
        let model = ZoomWindowModel(pageSize: CGSize(width: 800, height: 1000))
        let stroke = try #require(ZoomStrokeBuilder.build(samples: samples([CGPoint(x: 10, y: 10)]), model: model,
                                                          stripSize: CGSize(width: 500, height: 100), spec: spec()))
        #expect(stroke.path.count == 2)
    }

    @Test func noSamplesMakesNoStroke() {
        let model = ZoomWindowModel(pageSize: CGSize(width: 800, height: 1000))
        #expect(ZoomStrokeBuilder.build(samples: [], model: model, stripSize: CGSize(width: 500, height: 100), spec: spec()) == nil)
    }

    @Test func builtStrokeDrawsVisibleInk() throws {
        let model = ZoomWindowModel(pageSize: CGSize(width: 800, height: 1000))
        let stroke = try #require(ZoomStrokeBuilder.build(samples: samples([CGPoint(x: 0, y: 20), CGPoint(x: 300, y: 20)]),
                                                          model: model, stripSize: CGSize(width: 500, height: 100), spec: spec()))
        let drawing = PKDrawing(strokes: [stroke])
        #expect(!drawing.bounds.isEmpty)
        #expect(drawing.bounds.width > 40)
    }
}

@MainActor
@Suite struct ZoomWindowControllerTests {
    private func make(pages: Int = 1) throws -> (EditorFixture, ZoomWindowController) {
        let fixture = try EditorFixture(pages: pages)
        let controller = ZoomWindowController.controller(for: fixture.session)
        controller.stripLayoutChanged(size: CGSize(width: 600, height: 110), displayScale: 2)
        controller.activate()
        return (fixture, controller)
    }

    private func write(_ controller: ZoomWindowController, from a: CGFloat, to b: CGFloat) {
        let points = stride(from: a, through: b, by: 10).enumerated().map {
            StripSample(location: CGPoint(x: $0.element, y: 55), time: Double($0.offset) * 0.01, azimuth: 0, altitude: .pi / 2)
        }
        controller.strokeBegan([points[0]])
        controller.strokeMoved(Array(points.dropFirst().dropLast()))
        controller.strokeEnded([points.last!])
    }

    @Test func activatingFollowsTheCurrentPage() throws {
        let (fixture, controller) = try make()
        #expect(controller.pageID == fixture.firstPageID)
        #expect(controller.model.focusRect.minX >= 0)
    }

    @Test func writingInTheStripAddsAnUndoableStrokeToThePage() async throws {
        let (fixture, controller) = try make()
        let page = try fixture.page()
        controller.setAutoAdvance(false)
        write(controller, from: 20, to: 200)
        #expect(page.ink.strokes.count == 1)
        let stroke = try #require(page.ink.strokes.first)
        #expect(controller.model.focusRect.insetBy(dx: -1, dy: -1).contains(stroke.stroke.path.first!.location))

        await EditorFixture.settle()
        fixture.session.undo()
        #expect(page.ink.strokes.isEmpty)
    }

    @Test func writingNearTheRightEdgeAdvancesTheBox() throws {
        let (_, controller) = try make()
        let before = controller.model.focusOrigin
        write(controller, from: 20, to: 560)    // 560 / 600 is past the 0.8 trigger
        #expect(controller.model.focusOrigin.x > before.x)
        #expect(controller.pendingStrokes.isEmpty)
    }

    @Test func autoAdvanceOffKeepsTheBoxStill() throws {
        let (_, controller) = try make()
        controller.setAutoAdvance(false)
        let before = controller.model.focusOrigin
        write(controller, from: 20, to: 590)
        #expect(controller.model.focusOrigin == before)
    }

    @Test func newLineDropsTheBoxBelowTheCurrentLine() throws {
        let (_, controller) = try make()
        let before = controller.model.focusOrigin
        controller.newLine()
        #expect(controller.model.focusOrigin.y > before.y)
    }

    @Test func nudgeMovesTheBox() throws {
        let (_, controller) = try make()
        let before = controller.model.focusOrigin
        controller.nudge(.down)
        #expect(controller.model.focusOrigin.y > before.y)
    }

    @Test func cancelledStrokeWritesNothing() throws {
        let (fixture, controller) = try make()
        let page = try fixture.page()
        controller.strokeBegan([StripSample(location: CGPoint(x: 5, y: 5), time: 0, azimuth: 0, altitude: 1)])
        controller.strokeCancelled()
        #expect(page.ink.strokes.isEmpty)
        #expect(controller.liveSamples.isEmpty)
    }

    @Test func toolActivationShowsAndHidesThePanelState() throws {
        let fixture = try EditorFixture()
        let tool = ZoomWindowTool()
        tool.activate(in: fixture.session)
        let controller = ZoomWindowController.controller(for: fixture.session)
        #expect(controller.isActive)
        tool.deactivate(in: fixture.session)
        #expect(!controller.isActive)
    }
}

@MainActor
@Suite struct PageMirrorTests {
    @Test func signatureChangesWhenInkIsAdded() throws {
        let fixture = try EditorFixture()
        let page = try fixture.page()
        let before = PageMirror.signature(of: page)
        page.ink.edit("Add") { $0.append(TestInk.stroke(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 90, y: 10))) }
        #expect(PageMirror.signature(of: page) != before)
    }

    @Test func mirrorRendersTheCurrentPage() async throws {
        let fixture = try EditorFixture()
        let mirror = PageMirror()
        mirror.targetPixelWidth = 600
        mirror.start(editor: fixture.session) {}
        for _ in 0..<40 where mirror.image == nil { try await Task.sleep(for: .milliseconds(50)) }
        #expect(mirror.image != nil)
        #expect(mirror.pageID == fixture.firstPageID)
        mirror.stop()
        #expect(mirror.image == nil)
    }
}

@MainActor
@Suite struct PresentationControllerTests {
    @Test func startsOnDeviceWithoutADisplayAndStops() throws {
        let fixture = try EditorFixture()
        let controller = PresentationController()
        controller.start(editor: fixture.session)
        #expect(controller.machine.mode == .onDevice)
        controller.stop()
        #expect(controller.machine.mode == .idle)
        #expect(!controller.mirror.isRunning)
    }

    @Test func externalDisplayLifecycleDrivesTheMode() throws {
        let fixture = try EditorFixture()
        let controller = PresentationController()
        controller.displayConnected(sceneID: "ext-1")
        controller.displayConnected(sceneID: "ext-1")
        #expect(controller.machine.externalDisplayCount == 1)
        controller.start(editor: fixture.session)
        #expect(controller.machine.mode == .external)
        controller.displayDisconnected(sceneID: "ext-1")
        #expect(controller.machine.mode == .idle)
        #expect(controller.notice != nil)
    }

    @Test func optionsPersistAcrossInstances() {
        let defaults = UserDefaults.standard
        let saved = defaults.data(forKey: "present.options")
        defer { if let saved { defaults.set(saved, forKey: "present.options") } else { defaults.removeObject(forKey: "present.options") } }
        let controller = PresentationController()
        controller.options = PresentationOptions(hideToolbars: false, showLaser: false, showZoomWindow: true)
        #expect(PresentationController().options == controller.options)
    }
}

@MainActor
@Suite struct NotebookWindowActivityTests {
    @Test func activityRoundTripsTheNotebookID() {
        let id = UUID()
        let activity = NotebookWindowActivity.make(notebookID: id, title: "Chem")
        #expect(activity.activityType == NotebookWindowActivity.type)
        #expect(NotebookWindowActivity.notebookID(from: activity) == id)
        #expect(!activity.isEligibleForHandoff)
    }

    @Test func foreignActivitiesAreIgnored() {
        let other = NSUserActivity(activityType: "com.example.other")
        other.userInfo = [NotebookWindowActivity.notebookIDKey: UUID().uuidString]
        #expect(NotebookWindowActivity.notebookID(from: other) == nil)
        let broken = NotebookWindowActivity.make(notebookID: UUID(), title: "x")
        broken.userInfo = [NotebookWindowActivity.notebookIDKey: "not-a-uuid"]
        #expect(NotebookWindowActivity.notebookID(from: broken) == nil)
    }
}
