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
}
