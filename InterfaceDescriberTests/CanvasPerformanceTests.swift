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
        let fitted = Camera.fitting(everything, viewSize: viewSize, padding: 20)
        let anchor = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
        let cases: [(name: String, cameras: [Camera])] = [
            ("panning, everything visible", (0..<10).map { fitted.panned(byViewDX: Double($0), dy: 0) }),
            ("panning at 100 %, titles on every item", (0..<10).map { Camera(zoom: 1, panX: Double($0), panY: 0) }),
            (
                "pinching at about 100 %",
                (0..<10).map { Camera(zoom: 1).zoomed(to: 1 + 0.02 * Double($0), anchor: anchor) }
            ),
        ]
        for (name, cameras) in cases {
            let (average, drawn) = try timeRender(screen, cameras: cameras)
            print(
                String(
                    format: "Canvas render, 500 regions, %@: %.2f ms per frame, %d regions drawn", name, average, drawn)
            )
            XCTAssertLessThan(average, 50, name)
        }
        // Temporary spike breakdown at 100 %.
        let hundred = (0..<10).map { Camera(zoom: 1, panX: Double($0), panY: 0) }
        for skip in [
            ["titles"], ["fills"], ["borders"], ["grid"], ["bounds"], ["titles", "fills", "borders", "grid", "bounds"],
        ] {
            CanvasRenderer.skipped = Set(skip)
            let (average, _) = try timeRender(screen, cameras: hundred)
            print(String(format: "Breakdown at 100 %%, without %@: %.2f ms", skip.joined(separator: "+"), average))
        }
        CanvasRenderer.skipped = []
        let (oneX, _) = try timeRender(screen, cameras: hundred, scale: 1)
        print(String(format: "Breakdown at 100 %%, 1x bitmap: %.2f ms", oneX))
        let (_, drawn) = try timeRender(screen, cameras: [fitted])
        XCTAssertEqual(drawn, 500)
    }

    /// Draws the screen into a 1440 × 900 pt bitmap at 2× once per camera, after one untimed draw that lays out the
    /// titles, as the canvas would have done in earlier frames. Returns the average time in milliseconds and how
    /// many regions the first draw drew.
    @MainActor
    private func timeRender(_ screen: Screen, cameras: [Camera], scale: CGFloat = 2) throws -> (
        milliseconds: Double, drawn: Int
    ) {
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

        let titles = TitleCache()
        let dirtyRect = CGRect(origin: .zero, size: viewSize)
        func renderer(_ camera: Camera) -> CanvasRenderer {
            CanvasRenderer(screen: screen, camera: camera, gridSize: Snapping.defaultGridSize, titles: titles)
        }
        let drawn = renderer(cameras[0]).draw(in: dirtyRect)
        let start = Date()
        for camera in cameras {
            renderer(camera).draw(in: dirtyRect)
        }
        return (Date().timeIntervalSince(start) / Double(cameras.count) * 1000, drawn)
    }
}
