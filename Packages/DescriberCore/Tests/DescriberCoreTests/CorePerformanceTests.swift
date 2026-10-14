import XCTest

@testable import DescriberCore

/// How long the core work the app does for one event or one edit takes on the 500-region stress project. The canvas
/// builds a `ScrollLayout` and hit-tests on presses, drags gestures frame by frame, and performs a command on release;
/// the document re-encodes the package and fingerprints thumbnails after edits. These run without AppKit, so a change
/// to them can be timed anywhere: `scripts/bench.sh` runs them in a release build and `scripts/bench.sh --profile`
/// samples them. The budgets are loose so a slow runner or a debug build doesn't fail them; the times are printed.
final class CorePerformanceTests: XCTestCase {
    private var project: Project!
    private var screen: Screen!
    private var target: Region!
    private var press: CGPoint!

    override func setUpWithError() throws {
        project = Project.stressTest(regionCount: 500)
        screen = try XCTUnwrap(project.screens.first)
        target = try XCTUnwrap(screen.allRegions.first { $0.children.isEmpty && $0.frame.w >= 8 && $0.frame.h >= 8 })
        press = CGPoint(x: Double(target.frame.x) + 4, y: Double(target.frame.y) + 4)
    }

    /// Runs `body` `iterations` times, prints the average and returns it in milliseconds.
    private func time(_ name: String, iterations: Int, _ body: () throws -> Void) rethrows -> Double {
        let start = Date()
        for _ in 0..<iterations {
            try body()
        }
        let milliseconds = Date().timeIntervalSince(start) / Double(iterations) * 1000
        print(String(format: "Core, 500 regions, %@: %.3f ms", name, milliseconds))
        return milliseconds
    }

    func testLayoutAndHitTestingWithinBudget() {
        let index = time("region index", iterations: 50) { _ = RegionIndex(screen: screen) }
        let layout = time("scroll layout", iterations: 50) { _ = ScrollLayout(screen: screen) }
        let hit = time("hit test", iterations: 200) { _ = HitTesting.region(at: press, in: screen) }
        let parent = time("parent for a frame", iterations: 200) {
            _ = Parenting.parent(for: target.frame, excluding: target.id, in: screen)
        }
        XCTAssertLessThan(index, 20)
        XCTAssertLessThan(layout, 20)
        XCTAssertLessThan(hit, 20)
        XCTAssertLessThan(parent, 20)
    }

    func testGestureFramesWithinBudget() throws {
        let context = GestureContext(screen: screen, tool: .select, selection: [target.id])
        let pressAndRelease = time("press, drag and release", iterations: 20) {
            var gesture = CanvasGesture(pressAt: press, context: context)
            gesture.drag(to: CGPoint(x: press.x + 40, y: press.y + 24))
            _ = gesture.release(at: CGPoint(x: press.x + 40, y: press.y + 24))
        }
        var gesture = CanvasGesture(pressAt: press, context: context)
        var step = 0.0
        let dragFrame = time("drag frame", iterations: 200) {
            step += 1
            gesture.drag(to: CGPoint(x: press.x + step, y: press.y + step / 2))
        }
        XCTAssertLessThan(pressAndRelease, 50)
        XCTAssertLessThan(dragFrame, 8)
    }

    func testEditsWithinBudget() throws {
        let session = EditSession(project: project)
        let context = GestureContext(screen: screen, tool: .select, selection: [target.id])
        var gesture = CanvasGesture(pressAt: press, context: context)
        gesture.drag(to: CGPoint(x: press.x + 40, y: press.y + 24))
        let move = try XCTUnwrap(gesture.release(at: CGPoint(x: press.x + 40, y: press.y + 24)))
        let performAndUndo = try time("perform and undo a move", iterations: 20) {
            try session.perform(move)
            try session.undo()
        }

        let tree = ProjectPackage.write(project: project).tree
        let encode = time("encode the package after an edit", iterations: 10) {
            _ = ProjectPackage.write(project: project, previous: tree)
        }
        let fingerprint = time("thumbnail fingerprint", iterations: 50) {
            _ = ScreenThumbnail.fingerprint(of: screen)
        }
        let thumbnail = time("thumbnail rects", iterations: 50) {
            _ = ScreenThumbnail.rects(for: screen, width: 200, height: 125)
        }
        XCTAssertLessThan(performAndUndo, 50)
        XCTAssertLessThan(encode, 200)
        XCTAssertLessThan(fingerprint, 20)
        XCTAssertLessThan(thumbnail, 20)
    }
}
