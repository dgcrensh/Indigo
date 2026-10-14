import AppKit
import DescriberCore
import QuartzCore
import XCTest

@testable import InterfaceDescriber

/// The milestone 4 spike: how much main-thread work the canvas does for the 500-region stress project. Each region is
/// a layer, so a frame of panning or pinching is the time to update the layers (and redraw any title whose size
/// changed); compositing happens on the GPU. The target on a Mac is under 8 ms per frame; the assertions are looser
/// so a slow CI runner doesn't fail them, and the times are printed for the plan.
final class CanvasPerformanceTests: XCTestCase {
    private let viewSize = CGSize(width: 1440, height: 900)

    @MainActor
    private func makeCanvas() throws -> (CanvasView, Screen) {
        let screen = try XCTUnwrap(Project.stressTest(regionCount: 500).screens.first)
        let canvas = CanvasView(frame: CGRect(origin: .zero, size: viewSize))
        canvas.layoutSubtreeIfNeeded()
        canvas.gridSize = Snapping.defaultGridSize
        canvas.screen = screen
        return (canvas, screen)
    }

    /// Runs `step` for each value and returns the average time in milliseconds, including redrawing any titles the
    /// step marked for display.
    @MainActor
    private func time<Value>(_ canvas: CanvasView, _ values: [Value], step: (Value) -> Void) -> Double {
        let start = Date()
        for value in values {
            step(value)
            for box in canvas.regionsLayer.sublayers ?? [] {
                for sublayer in box.sublayers ?? [] {
                    sublayer.displayIfNeeded()
                }
            }
        }
        return Date().timeIntervalSince(start) / Double(values.count) * 1000
    }

    @MainActor
    func testStressProjectUpdatesWithinBudget() throws {
        let (canvas, screen) = try makeCanvas()
        XCTAssertEqual(canvas.regionLayerCount, 500)
        XCTAssertEqual(canvas.regionsLayer.sublayers?.count, 500)
        XCTAssertTrue(canvas.stage.contentsAreFlipped())

        let anchor = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
        canvas.camera = Camera(zoom: 1)
        let reload = time(canvas, Array(0..<5)) { _ in canvas.reload() }
        let pan = time(canvas, Array(1...20)) { offset in
            canvas.camera = Camera(zoom: 1, panX: Double(offset), panY: Double(offset))
        }
        let pinch = time(canvas, Array(1...20)) { step in
            canvas.camera = Camera(zoom: 1).zoomed(to: 1 - 0.03 * Double(step), anchor: anchor)
        }
        let everything = screen.allRegions.map(\.frame.cgRect).reduce(screen.canvasBounds.cgRect) { $0.union($1) }
        let fitted = Camera.fitting(everything, viewSize: viewSize, padding: 20)
        let pinchFitted = time(canvas, Array(1...20)) { step in
            canvas.camera = fitted.zoomed(to: fitted.zoom * (1 + 0.01 * Double(step)), anchor: anchor)
        }

        for (name, milliseconds) in [
            ("reload after an edit", reload), ("pan", pan), ("pinch at about 100 %", pinch),
            ("pinch with everything visible", pinchFitted),
        ] {
            print(String(format: "Canvas, 500 regions, %@: %.2f ms per frame", name, milliseconds))
        }
        XCTAssertLessThan(pan, 16)
        XCTAssertLessThan(pinch, 50)
        XCTAssertLessThan(pinchFitted, 50)
        XCTAssertLessThan(reload, 100)
    }

    @MainActor
    func testPanningMovesLayersWithoutResizingThem() throws {
        let (canvas, _) = try makeCanvas()
        canvas.camera = Camera(zoom: 2)
        let box = try XCTUnwrap(canvas.regionsLayer.sublayers?.first)
        let size = box.bounds.size
        canvas.camera = Camera(zoom: 2, panX: 50, panY: 25)
        XCTAssertEqual(box.bounds.size, size)
        XCTAssertEqual(canvas.regionsLayer.position, CGPoint(x: -100, y: -50))
        // The first container is at (16, 16) and 340 pt wide.
        XCTAssertEqual(box.frame, CGRect(x: 32, y: 32, width: 680, height: 600))
    }

    // MARK: Gestures (milestone 12)

    /// A window on a document holding the 500-region stress project, with its canvas the size the timings assume.
    @MainActor
    private func makeStressWindow() throws -> (Document, DocumentWindowController, CanvasViewController) {
        let document = Document()
        document.model.replaceProject(with: .stressTest(regionCount: 500))
        document.makeWindowControllers()
        let controller = try XCTUnwrap(document.windowControllers.first as? DocumentWindowController)
        controller.window?.setContentSize(viewSize)
        controller.window?.layoutIfNeeded()
        document.undoManager?.groupsByEvent = false
        let canvas = controller.canvasController
        canvas.update()
        canvas.canvasView.camera = Camera(zoom: 1)
        XCTAssertEqual(canvas.canvasView.regionLayerCount, 500)
        return (document, controller, canvas)
    }

    /// Presses at `start`, drags there by `delta` in 20 frames and releases, as one undo group. Returns the average
    /// time of a drag frame in milliseconds, including redrawing anything the frame marked for display.
    @MainActor
    private func timeDrag(
        _ canvas: CanvasViewController, in document: Document, from start: CGPoint, by delta: CGVector
    ) -> Double {
        let frames = 20
        let end = CGPoint(x: start.x + delta.dx, y: start.y + delta.dy)
        document.undoManager?.beginUndoGrouping()
        canvas.canvasPressed(at: start, modifiers: [])
        let begin = Date()
        for frame in 1...frames {
            let progress = Double(frame) / Double(frames)
            canvas.canvasDragged(
                to: CGPoint(x: start.x + delta.dx * progress, y: start.y + delta.dy * progress), optionHeld: false)
            canvas.canvasView.layer?.displayIfNeeded()
            for box in canvas.canvasView.regionsLayer.sublayers ?? [] {
                for sublayer in box.sublayers ?? [] {
                    sublayer.displayIfNeeded()
                }
            }
        }
        let milliseconds = Date().timeIntervalSince(begin) / Double(frames) * 1000
        canvas.canvasReleased(at: end, optionHeld: false)
        document.undoManager?.endUndoGrouping()
        canvas.update()
        return milliseconds
    }

    @MainActor
    func testGesturesOnTheStressProjectStayWithinBudget() throws {
        let (document, controller, canvas) = try makeStressWindow()
        defer { controller.close() }
        let session = document.model.session
        let screen = try XCTUnwrap(document.model.activeScreen)
        let container = try XCTUnwrap(screen.regions.first)
        let item = try XCTUnwrap(container.children.first?.children.first)
        XCTAssertEqual(item.frame, Frame(x: 40, y: 40, w: 92, h: 32))
        var times: [(String, Double)] = []

        // Item 1.1.1, dragged across the screen.
        let moveOne = timeDrag(canvas, in: document, from: CGPoint(x: 86, y: 56), by: CGVector(dx: 400, dy: 240))
        XCTAssertEqual(session.undoDepth, 1)
        XCTAssertEqual(session.undoActionName, "Move Region")
        times.append(("move one region", moveOne))

        // Every region, dragged by container 1's bottom margin.
        canvas.selectAll()
        XCTAssertEqual(document.model.selection.count, 500)
        let moveAll = timeDrag(canvas, in: document, from: CGPoint(x: 24, y: 310), by: CGVector(dx: 160, dy: 96))
        XCTAssertEqual(session.undoDepth, 2)
        XCTAssertGreaterThan(container.frame.x, 16, "the whole selection moved")
        times.append(("move all 500", moveAll))

        // Container 1, its children inside, by its bottom-right handle.
        document.model.selection = [container.id]
        canvas.update()
        let corner = CGPoint(x: container.frame.maxX, y: container.frame.maxY)
        let resize = timeDrag(canvas, in: document, from: corner, by: CGVector(dx: 200, dy: 120))
        XCTAssertEqual(session.undoDepth, 3)
        XCTAssertEqual(session.undoActionName, "Resize Region")
        times.append(("resize a container", resize))

        // A large region drawn over most of the screen.
        canvas.choose(.region)
        let draw = timeDrag(canvas, in: document, from: CGPoint(x: 8, y: 8), by: CGVector(dx: 1200, dy: 800))
        XCTAssertNotNil(document.model.details, "the drawn region opened in the panel")
        document.model.closeDetails()
        times.append(("draw a region", draw))

        for (name, milliseconds) in times {
            print(String(format: "Canvas, 500 regions, %@: %.2f ms per drag frame", name, milliseconds))
            XCTAssertLessThan(milliseconds, 16, name)
        }
    }
}
