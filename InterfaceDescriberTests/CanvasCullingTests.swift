import AppKit
import DescriberCore
import QuartzCore
import XCTest

@testable import InterfaceDescriber

/// The canvas mounts only the regions near the view: those in the covered rect, plus the selection and any previewed
/// regions (milestone 20).
final class CanvasCullingTests: XCTestCase {
    private let viewSize = CGSize(width: 1440, height: 900)

    /// A canvas showing the 500-region stress screen at 100 %, its top-left corner at the screen's origin.
    @MainActor
    private func makeCanvas() throws -> (CanvasView, Screen) {
        let screen = try XCTUnwrap(Project.stressTest(regionCount: 500).screens.first)
        let canvas = CanvasView(frame: CGRect(origin: .zero, size: viewSize))
        canvas.layoutSubtreeIfNeeded()
        canvas.screen = screen
        canvas.camera = Camera(zoom: 1)
        return (canvas, screen)
    }

    /// The regions whose frames meet the covered rect for `camera`: none of the stress screen's regions scroll, so
    /// each is drawn at its own frame.
    private func covered(on screen: Screen, by camera: Camera) -> Set<RegionID> {
        let rect = CanvasCoverage(camera: camera, viewSize: viewSize).covered
        return Set(screen.allRegions.filter { $0.frame.cgRect.intersects(rect) }.map(\.id))
    }

    /// Checks that the mounted boxes are in draw order and laid out where their regions are drawn.
    @MainActor
    private func assertMountedInDrawOrder(
        _ canvas: CanvasView, _ screen: Screen, file: StaticString = #filePath, line: UInt = #line
    ) {
        let mounted = canvas.mountedRegionIDs
        let order = canvas.mountedRegionOrder
        XCTAssertEqual(order, screen.allRegions.map(\.id).filter(mounted.contains), file: file, line: line)
        XCTAssertEqual(canvas.regionsLayer.sublayers?.count, mounted.count, file: file, line: line)
        let zoom = canvas.camera.zoom
        for (id, box) in zip(order, canvas.regionsLayer.sublayers ?? []) {
            guard let frame = canvas.drawnFrame(of: id) else {
                XCTFail("no drawn frame for \(id)", file: file, line: line)
                continue
            }
            XCTAssertEqual(box.frame, RegionLayers.zoomed(frame, zoom), "\(id)", file: file, line: line)
        }
    }

    @MainActor
    func testOnlyRegionsInTheCoveredRectAreMounted() throws {
        let (canvas, screen) = try makeCanvas()
        XCTAssertEqual(canvas.regionLayerCount, 500, "every region has layers or is due them")
        // Container rows 1 to 4 whole, and the top of row 5: its containers, their first rows and those rows' items.
        XCTAssertEqual(canvas.mountedRegionCount, 16 * 21 + 4 * 5)
        XCTAssertEqual(canvas.mountedRegionIDs, covered(on: screen, by: canvas.camera))
        assertMountedInDrawOrder(canvas, screen)
    }

    @MainActor
    func testAPanInsideTheMarginChangesNoMounts() throws {
        let (canvas, _) = try makeCanvas()
        let boxes = try XCTUnwrap(canvas.regionsLayer.sublayers)
        canvas.camera = Camera(zoom: 1, panX: 300, panY: 316)
        XCTAssertTrue((canvas.regionsLayer.sublayers ?? []).elementsEqual(boxes, by: ===))
    }

    @MainActor
    func testPanningPastTheMarginMountsTheNextRowsAndUnmountsTheOnesThatLeft() throws {
        let (canvas, screen) = try makeCanvas()
        let firstRow = try XCTUnwrap(screen.regions.first?.children.first)
        let lastContainer = try XCTUnwrap(screen.regions.last)
        XCTAssertTrue(canvas.mountedRegionIDs.contains(firstRow.id))
        XCTAssertFalse(canvas.mountedRegionIDs.contains(lastContainer.id))

        // Down two rows of containers.
        canvas.camera = Camera(zoom: 1, panX: 0, panY: 632)
        XCTAssertEqual(canvas.mountedRegionIDs, covered(on: screen, by: canvas.camera))
        XCTAssertTrue(canvas.mountedRegionIDs.contains(lastContainer.id), "the last row of containers mounted")
        XCTAssertFalse(canvas.mountedRegionIDs.contains(firstRow.id), "the first container's top row unmounted")
        assertMountedInDrawOrder(canvas, screen)

        // And back, where the layers made before are used again.
        canvas.camera = Camera(zoom: 1)
        XCTAssertEqual(canvas.mountedRegionIDs, covered(on: screen, by: canvas.camera))
        assertMountedInDrawOrder(canvas, screen)
    }

    @MainActor
    func testZoomingOutToFitMountsEverything() throws {
        let (canvas, screen) = try makeCanvas()
        let everything = screen.allRegions.map(\.frame.cgRect).reduce(screen.canvasBounds.cgRect) { $0.union($1) }
        canvas.camera = Camera.fitting(everything, viewSize: viewSize, padding: 20)
        XCTAssertEqual(canvas.mountedRegionCount, 500)
        assertMountedInDrawOrder(canvas, screen)
        XCTAssertTrue(canvas.isTextSettled)
    }

    @MainActor
    func testASelectedRegionStaysMountedWhileSelected() throws {
        let (canvas, screen) = try makeCanvas()
        let item = try XCTUnwrap(screen.regions.first?.children.first?.children.first)
        canvas.selection = [item.id]
        canvas.camera = Camera(zoom: 1, panX: 3000, panY: 3000)
        XCTAssertEqual(canvas.mountedRegionIDs, [item.id], "only the selection is near nothing else")
        XCTAssertEqual(canvas.selectedLayerIDs, [item.id])
        assertMountedInDrawOrder(canvas, screen)
        canvas.selection = []
        XCTAssertEqual(canvas.mountedRegionCount, 0)
        XCTAssertEqual(canvas.selectedLayerIDs, [])
    }

    @MainActor
    func testPreviewedRegionsStayMountedThroughAGesture() throws {
        let (canvas, screen) = try makeCanvas()
        let item = try XCTUnwrap(screen.regions.first?.children.first?.children.first)
        canvas.preview = .frames([item.id: Frame(x: 4000, y: 4000, w: 92, h: 32)])
        canvas.camera = Camera(zoom: 1, panX: 3800, panY: 3800)
        XCTAssertEqual(canvas.mountedRegionIDs, [item.id])
        XCTAssertEqual(canvas.drawnFrame(of: item.id), Frame(x: 4000, y: 4000, w: 92, h: 32))
        canvas.preview = .none
        XCTAssertEqual(canvas.mountedRegionCount, 0)
        XCTAssertEqual(canvas.drawnFrame(of: item.id), item.frame, "back where it is drawn")
    }

    @MainActor
    func testARegionEditedWhileUnmountedIsUpToDateWhenItMounts() throws {
        let (canvas, screen) = try makeCanvas()
        let lastContainer = try XCTUnwrap(screen.regions.last)
        canvas.camera = Camera(zoom: 1, panX: 0, panY: 632)
        canvas.visibleDescriptions = [lastContainer.id]
        canvas.camera = Camera(zoom: 1)
        XCTAssertFalse(canvas.mountedRegionIDs.contains(lastContainer.id))
        lastContainer.frame = lastContainer.frame.offsetBy(dx: 8, dy: 0)
        lastContainer.description = "Described"
        canvas.visibleDescriptions = []
        canvas.reload()
        canvas.camera = Camera(zoom: 1, panX: 0, panY: 632)
        XCTAssertTrue(canvas.mountedRegionIDs.contains(lastContainer.id))
        XCTAssertEqual(canvas.drawnFrame(of: lastContainer.id), lastContainer.frame)
        XCTAssertEqual(canvas.describedLayerIDs, [], "the description was hidden while it was away")
        assertMountedInDrawOrder(canvas, screen)
    }

    @MainActor
    func testResizingTheViewCoversTheNewArea() throws {
        let (canvas, screen) = try makeCanvas()
        canvas.setFrameSize(CGSize(width: 1440, height: 2400))
        let rect = CanvasCoverage(camera: canvas.camera, viewSize: canvas.bounds.size).covered
        let expected = Set(screen.allRegions.filter { $0.frame.cgRect.intersects(rect) }.map(\.id))
        XCTAssertEqual(canvas.mountedRegionIDs, expected)
        XCTAssertEqual(canvas.mountedRegionCount, 500)
    }
}
