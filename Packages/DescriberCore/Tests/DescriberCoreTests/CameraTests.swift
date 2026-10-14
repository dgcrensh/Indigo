import XCTest

@testable import DescriberCore

final class CameraTests: XCTestCase {
    private let viewSize = CGSize(width: 800, height: 600)

    private func assertEqual(_ a: CGPoint, _ b: CGPoint, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(a.y, b.y, accuracy: 1e-9, file: file, line: line)
    }

    func testViewAndScreenPointsRoundTrip() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 123.5, y: -40), CGPoint(x: -900, y: 2000)]
        for zoom in [0.1, 1.0 / 3, 1, 2.5, 8] {
            let camera = Camera(zoom: zoom, panX: -37.25, panY: 410)
            for point in points {
                assertEqual(camera.screenPoint(fromView: camera.viewPoint(fromScreen: point)), point)
                assertEqual(camera.viewPoint(fromScreen: camera.screenPoint(fromView: point)), point)
            }
        }
    }

    func testPanIsTheScreenPointAtTheTopLeft() {
        let camera = Camera(zoom: 2, panX: 100, panY: 50)
        assertEqual(camera.screenPoint(fromView: .zero), CGPoint(x: 100, y: 50))
        assertEqual(camera.viewPoint(fromScreen: CGPoint(x: 110, y: 60)), CGPoint(x: 20, y: 20))
        XCTAssertEqual(camera.visibleRect(viewSize: viewSize), CGRect(x: 100, y: 50, width: 400, height: 300))
        XCTAssertEqual(
            camera.viewRect(fromScreen: CGRect(x: 110, y: 60, width: 10, height: 5)),
            CGRect(x: 20, y: 20, width: 20, height: 10))
    }

    func testZoomingKeepsTheAnchorFixed() {
        let camera = Camera(zoom: 1.5, panX: 20, panY: -30)
        let anchor = CGPoint(x: 312, y: 97)
        let fixed = camera.screenPoint(fromView: anchor)
        for zoom in [0.2, 1, 3.7] {
            let zoomed = camera.zoomed(to: zoom, anchor: anchor)
            XCTAssertEqual(zoomed.zoom, zoom, accuracy: 1e-12)
            assertEqual(zoomed.screenPoint(fromView: anchor), fixed)
        }
    }

    func testZoomIsClamped() {
        XCTAssertEqual(Camera(zoom: 0.01).zoom, Camera.minimumZoom)
        XCTAssertEqual(Camera(zoom: 50).zoom, Camera.maximumZoom)
        let anchor = CGPoint(x: 10, y: 10)
        let camera = Camera(zoom: 4, panX: 5, panY: 5)
        let zoomed = camera.zoomed(to: 100, anchor: anchor)
        XCTAssertEqual(zoomed.zoom, Camera.maximumZoom)
        assertEqual(zoomed.screenPoint(fromView: anchor), camera.screenPoint(fromView: anchor))
        XCTAssertEqual(Camera(zoom: 8).zoomedIn(anchor: .zero).zoom, 8)
        XCTAssertEqual(Camera(zoom: 0.1).zoomedOut(anchor: .zero).zoom, 0.1)
    }

    func testZoomInAndOutFollowTheLadder() {
        var camera = Camera(zoom: 1)
        var upward: [Double] = []
        for _ in 0..<8 {
            camera = camera.zoomedIn(anchor: .zero)
            upward.append(camera.zoom)
        }
        XCTAssertEqual(upward, [1.25, 1.5, 2, 3, 4, 6, 8, 8])
        XCTAssertEqual(Camera(zoom: 1).zoomedOut(anchor: .zero).zoom, 0.75)
        XCTAssertEqual(Camera(zoom: 0.75).zoomedOut(anchor: .zero).zoom, 2.0 / 3, accuracy: 1e-12)
        // Between steps, the next step in each direction.
        XCTAssertEqual(Camera(zoom: 1.1).zoomedIn(anchor: .zero).zoom, 1.25)
        XCTAssertEqual(Camera(zoom: 1.1).zoomedOut(anchor: .zero).zoom, 1)
    }

    func testPanningMovesContentWithTheDrag() {
        let camera = Camera(zoom: 2, panX: 0, panY: 0)
        let point = CGPoint(x: 50, y: 50)
        let before = camera.viewPoint(fromScreen: point)
        let after = camera.panned(byViewDX: 30, dy: -10).viewPoint(fromScreen: point)
        assertEqual(after, CGPoint(x: before.x + 30, y: before.y - 10))
    }

    func testFittingCentersTheRectWithinThePadding() {
        let rect = CGRect(x: 0, y: 0, width: 393, height: 852)
        let camera = Camera.fitting(rect, viewSize: viewSize, padding: 40, maximumZoom: 1)
        let shown = camera.viewRect(fromScreen: rect)
        XCTAssertEqual(shown.height, 520, accuracy: 1e-9)
        XCTAssertEqual(shown.midX, 400, accuracy: 1e-9)
        XCTAssertEqual(shown.midY, 300, accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(shown.minX, 40)

        // A small rect stops at the maximum zoom.
        let small = CGRect(x: 10, y: 10, width: 100, height: 100)
        let capped = Camera.fitting(small, viewSize: viewSize, padding: 40, maximumZoom: 1)
        XCTAssertEqual(capped.zoom, 1)
        XCTAssertEqual(capped.viewRect(fromScreen: small).midX, 400, accuracy: 1e-9)
    }

    func testActualSizeCentersAtOneHundredPercent() {
        let rect = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let camera = Camera.actualSize(centering: rect, viewSize: viewSize)
        XCTAssertEqual(camera.zoom, 1)
        XCTAssertEqual(camera.viewRect(fromScreen: rect).midX, 400, accuracy: 1e-9)
        XCTAssertEqual(camera.viewRect(fromScreen: rect).midY, 300, accuracy: 1e-9)
    }

    func testConvertsToAndFromEditorState() {
        let offsets = [RegionID("a"): ScrollOffset(x: 0, y: 40)]
        let state = ScreenEditorState(zoom: 2, panX: 3, panY: 4, gridSize: 12, scrollOffsets: offsets)
        let camera = Camera(state)
        XCTAssertEqual(camera, Camera(zoom: 2, panX: 3, panY: 4))
        let updated = Camera(zoom: 0.5, panX: -1, panY: 7).applied(to: state)
        XCTAssertEqual(updated, ScreenEditorState(zoom: 0.5, panX: -1, panY: 7, gridSize: 12, scrollOffsets: offsets))
    }
}
