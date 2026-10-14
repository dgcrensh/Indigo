import AppKit
import DescriberCore
import QuartzCore
import XCTest

@testable import InterfaceDescriber

/// The canvas's main-thread time per action with its window on screen, including the Core Animation commit
/// (`CATransaction.flush()`), which `CanvasPerformanceTests` leaves out and which is most of the cost on a Mac
/// (`real-hardware-profile.md` in the project files). Prints one line per timing at 500, 2,000 and 5,000 regions so
/// each milestone's before and after show up in CI. Only the 500-region pan, pinch and nudge are asserted, loosely,
/// as CI runners are slow.
final class OnScreenPerformanceTests: XCTestCase {
    private let viewSize = CGSize(width: 1440, height: 900)

    /// A shown window on a document holding the stress project, and how long opening it took in milliseconds.
    @MainActor
    private func makeWindow(regionCount: Int) throws -> (Document, DocumentWindowController, Double) {
        let start = CACurrentMediaTime()
        let document = Document()
        document.model.replaceProject(with: .stressTest(regionCount: regionCount))
        document.makeWindowControllers()
        let controller = try XCTUnwrap(document.windowControllers.first as? DocumentWindowController)
        controller.window?.setContentSize(viewSize)
        controller.showWindow(nil)
        controller.window?.layoutIfNeeded()
        controller.canvasController.update()
        controller.window?.displayIfNeeded()
        CATransaction.flush()
        let open = (CACurrentMediaTime() - start) * 1000
        return (document, controller, open)
    }

    /// Lets timers and the run loop's own work run, as between frames on screen.
    private func settle(_ seconds: Double) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    /// Runs `step` for each of `steps` frames and returns each frame's time in milliseconds, commit included.
    @MainActor
    private func time(_ steps: Int, pause: Double = 0, _ step: (Int) -> Void) -> [Double] {
        (0..<steps).map { index in
            let start = CACurrentMediaTime()
            step(index)
            CATransaction.flush()
            let milliseconds = (CACurrentMediaTime() - start) * 1000
            if pause > 0 { settle(pause) }
            return milliseconds
        }
    }

    private static func median(_ samples: [Double]) -> Double {
        let sorted = samples.sorted()
        return sorted.isEmpty ? 0 : sorted[sorted.count / 2]
    }

    private static func line(_ count: Int, _ name: String, _ samples: [Double]) -> String {
        String(
            format: "On screen, %d regions, %@: median %.2f ms, max %.2f ms", count, name, median(samples),
            samples.max() ?? 0)
    }

    @MainActor
    func testCanvasTimingsOnScreen() throws {
        for count in [500, 2000, 5000] {
            let (document, controller, open) = try makeWindow(regionCount: count)
            defer { controller.close() }
            let canvas = controller.canvasController
            let view = canvas.canvasView
            let screen = try XCTUnwrap(document.model.activeScreen)
            let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
            canvas.setGridSize(8)
            view.change(to: Camera(zoom: 1))
            CATransaction.flush()
            settle(0.2)
            var lines = [String(format: "On screen, %d regions, show the screen in a new window: %.2f ms", count, open)]

            // A pan step at 100 %, as a mouse wheel or the first event of a trackpad scroll makes, off every region.
            let pan = time(60) { step in
                let dx = step % 60 < 30 ? -6.0 : 6.0
                view.simulateScroll(at: CGPoint(x: -100, y: -100), dx: dx, dy: dx / 2)
            }
            lines.append(Self.line(count, "pan at 100 %", pan))

            // A pinch run around 100 %: out, then back in.
            let pinch = time(60) { step in
                let factor = step < 30 ? 0.985 : 1 / 0.985
                view.change(to: view.camera.zoomed(to: view.camera.zoom * factor, anchor: center))
            }
            view.settleText()
            lines.append(Self.line(count, "pinch frame at 100 %", pinch))

            let everything = screen.allRegions.map(\.frame.cgRect).reduce(screen.canvasBounds.cgRect) { $0.union($1) }
            let fitted = Camera.fitting(everything, viewSize: view.bounds.size, padding: 20)
            view.change(to: fitted)
            CATransaction.flush()
            settle(0.2)
            let pinchFitted = time(60) { step in
                let factor = step < 30 ? 1.01 : 1 / 1.01
                view.change(to: view.camera.zoomed(to: view.camera.zoom * factor, anchor: center))
            }
            view.settleText()
            lines.append(Self.line(count, "pinch frame fitted", pinchFitted))
            view.change(to: Camera(zoom: 1))
            CATransaction.flush()
            settle(0.2)

            // Zoom commands far enough apart that each fits the text at once, as a keyboard shortcut does.
            let zoom = time(6, pause: 0.2) { step in
                if step % 2 == 0 { canvas.zoomOut() } else { canvas.zoomIn() }
            }
            lines.append(Self.line(count, "zoom command from 100 %", zoom))

            // One region retitled, as each keystroke in the details panel does.
            let item = try XCTUnwrap(screen.regions.first?.children.first?.children.first)
            let retitle = time(20) { step in
                item.title = "Retitled \(step)"
                document.model.noteChange()
                canvas.update()
            }
            lines.append(Self.line(count, "reload after retitling one region", retitle))

            document.model.selection = [item.id]
            canvas.update()
            let nudgeOne = time(20) { step in
                canvas.nudge(step % 2 == 0 ? .nudgeRight : .nudgeDown)
                canvas.update()
            }
            lines.append(Self.line(count, "nudge one region", nudgeOne))

            canvas.selectAll()
            canvas.update()
            let nudgeAll = time(20) { step in
                canvas.nudge(step % 2 == 0 ? .nudgeRight : .nudgeDown)
                canvas.update()
            }
            lines.append(Self.line(count, "nudge every region", nudgeAll))
            document.model.selection = []
            canvas.update()
            document.undoManager?.removeAllActions()

            for line in lines {
                print(line)
            }
            if count == 500 {
                XCTAssertLessThan(Self.median(pan), 16, "pan")
                XCTAssertLessThan(Self.median(pinch), 16, "pinch")
                XCTAssertLessThan(Self.median(nudgeOne), 16, "nudge one")
                XCTAssertLessThan(Self.median(nudgeAll), 16, "nudge every region")
            }
        }
    }
}
