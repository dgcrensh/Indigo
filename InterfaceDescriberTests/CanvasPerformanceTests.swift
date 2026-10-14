import AppKit
import DescriberCore
import XCTest

@testable import InterfaceDescriber

/// The milestone 4 spike: how long a full redraw of the 500-region stress project takes. The target on a Mac is
/// under 8 ms; the assertion is looser so a slow CI runner doesn't fail it, and the time is printed for the plan.
final class CanvasPerformanceTests: XCTestCase {
    private let viewSize = CGSize(width: 1440, height: 900)

    @MainActor
    func testStressProjectRendersWithinBudget() throws {
        let screen = try XCTUnwrap(Project.stressTest(regionCount: 500).screens.first)
        let everything = screen.allRegions.map(\.frame.cgRect).reduce(screen.canvasBounds.cgRect) { $0.union($1) }
        let cameras = [
            ("everything fitted", Camera.fitting(everything, viewSize: viewSize, padding: 20)),
            ("100 %, titles on every item", Camera(zoom: 1)),
        ]
        for (name, camera) in cameras {
            let (average, drawn) = try timeRender(screen, camera: camera)
            print(
                String(
                    format: "Canvas render, 500 regions, %@: %.2f ms per frame, %d regions drawn", name, average, drawn)
            )
            XCTAssertLessThan(average, 50, name)
            if name == "everything fitted" {
                XCTAssertEqual(drawn, 500)
            }
        }
    }

    /// Draws the screen into a 1440 × 900 pt bitmap at 2× ten times, and returns the average time in milliseconds
    /// and how many regions each draw drew.
    @MainActor
    private func timeRender(_ screen: Screen, camera: Camera) throws -> (milliseconds: Double, drawn: Int) {
        let scale: CGFloat = 2
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: Int(viewSize.width * scale),
                height: Int(viewSize.height * scale),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.translateBy(x: 0, y: viewSize.height * scale)
        context.scaleBy(x: scale, y: -scale)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)

        let renderer = CanvasRenderer(screen: screen, camera: camera, gridSize: Snapping.defaultGridSize)
        let dirtyRect = CGRect(origin: .zero, size: viewSize)
        let drawn = renderer.draw(in: dirtyRect)  // Warms up font and color caches.
        let runs = 10
        let start = Date()
        for _ in 0..<runs {
            renderer.draw(in: dirtyRect)
        }
        return (Date().timeIntervalSince(start) / Double(runs) * 1000, drawn)
    }
}
