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
    private func time(
        _ name: String, regions: Int = 500, iterations: Int, _ body: () throws -> Void
    ) rethrows -> Double {
        let start = Date()
        for _ in 0..<iterations {
            try body()
        }
        let milliseconds = Date().timeIntervalSince(start) / Double(iterations) * 1000
        print(String(format: "Core, %d regions, %@: %.3f ms", regions, name, milliseconds))
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

    /// Edits that touch many regions at once: everything selected and nudged, a container shrunk so its rows fall out,
    /// and two dozen containers pasted. Each is performed and undone.
    func testBulkEditsWithinBudget() throws {
        let session = EditSession(project: project)
        let everything = screen.allRegions.map(\.id)
        let moveAll = try time("perform and undo a select-all move", iterations: 20) {
            try session.perform(MoveRegions(screen: screen.id, regions: everything, dx: 8, dy: 0))
            try session.undo()
        }

        let container = try XCTUnwrap(screen.regions.first)
        var shrunk = container.frame
        shrunk.h = 12
        let shed = try time("perform and undo a resize shedding 5 rows", iterations: 20) {
            try session.perform(ResizeRegion(screen: screen.id, region: container.id, frame: shrunk))
            try session.undo()
        }

        let copies = Array(screen.regions.prefix(24))
        let paste = try time("perform and undo pasting 24 containers", iterations: 10) {
            try session.perform(PasteRegions(screen: screen.id, regions: copies))
            try session.undo()
        }
        XCTAssertLessThan(moveAll, 50)
        XCTAssertLessThan(shed, 50)
        XCTAssertLessThan(paste, 50)
    }

    /// Autosave: the 500-region screen written to text, and a ten-screen project written after retitling one region,
    /// with and without a cache warmed by the write before.
    func testPackageWritesWithinBudget() throws {
        let screenValue = ProjectEncoding.screen(screen, in: project)
        let text = time("write a screen's text", iterations: 20) { _ = OrderedJSONWriter.data(screenValue) }

        let large = Project.stressTest(regionCount: 500, screenCount: 10)
        let session = EditSession(project: large)
        let region = try XCTUnwrap(large.screens[4].regions.first)
        var tree = ProjectPackage.write(project: large).tree
        var edit = 0
        /// Retitles the region, then times only the write that follows.
        func writeAfterRetitle(_ name: String, cache: PackageEncodingCache?) throws -> Double {
            var elapsed: TimeInterval = 0
            let iterations = 10
            for _ in 0..<iterations {
                edit += 1
                try session.perform(RegionCommands.setTitle("Retitled \(edit)", of: region.id))
                let start = Date()
                let result = ProjectPackage.write(project: large, previous: tree, cache: cache)
                elapsed += Date().timeIntervalSince(start)
                tree = ProjectPackage.applying(result.changes, to: tree)
            }
            let milliseconds = elapsed / Double(iterations) * 1000
            print(String(format: "Core, 5000 regions, %@: %.3f ms", name, milliseconds))
            return milliseconds
        }
        let uncached = try writeAfterRetitle("write 10 screens after a retitle", cache: nil)
        let cache = PackageEncodingCache()
        tree = ProjectPackage.write(project: large, previous: tree, cache: cache).tree
        let cached = try writeAfterRetitle("write 10 screens after a retitle, cached", cache: cache)
        XCTAssertLessThan(text, 50)
        XCTAssertLessThan(uncached, 500)
        XCTAssertLessThan(cached, 500)
    }

    /// Milestone 23: autosave after one nudge on a 40-screen project of 300 regions each, with the encoding cache,
    /// with and without the session's generations. With them, only the nudged screen is built and encoded.
    func testWriteAfterANudgeOnFortyScreensWithinBudget() throws {
        let large = Project.stressTest(regionCount: 300, screenCount: 40)
        let session = EditSession(project: large)
        let cache = PackageEncodingCache()
        var tree = ProjectPackage.write(project: large, cache: cache, generations: session.generations).tree
        var nudges = 0
        /// Nudges a region on a different screen each time, then times only the write that follows.
        func writeAfterNudge(_ name: String, generations: Bool) throws -> Double {
            var elapsed: TimeInterval = 0
            let iterations = 20
            for _ in 0..<iterations {
                nudges += 1
                let screen = large.screens[(nudges * 7) % large.screens.count]
                let region = try XCTUnwrap(screen.allRegions.last)
                try session.perform(
                    MoveRegions(screen: screen.id, regions: [region.id], dx: nudges % 2 == 0 ? 1 : -1, dy: 0))
                let start = Date()
                let result = ProjectPackage.write(
                    project: large, previous: tree, cache: cache, generations: generations ? session.generations : nil)
                elapsed += Date().timeIntervalSince(start)
                XCTAssertEqual(result.changed.count, 1)
                tree = ProjectPackage.applying(result.changes, to: tree)
            }
            let milliseconds = elapsed / Double(iterations) * 1000
            print(String(format: "Core, 12000 regions, %@: %.3f ms", name, milliseconds))
            return milliseconds
        }
        let without = try writeAfterNudge("write 40 screens after a nudge, cached", generations: false)
        let with = try writeAfterNudge("write 40 screens after a nudge, cached with generations", generations: true)
        XCTAssertLessThan(with, without / 5)
    }

    func testSelectAllMoveOnFiveThousandRegionsWithinBudget() throws {
        let project = Project.stressTest(regionCount: 5000)
        let screen = try XCTUnwrap(project.screens.first)
        let session = EditSession(project: project)
        let everything = screen.allRegions.map(\.id)
        let moveAll = try time("perform and undo a select-all move", regions: 5000, iterations: 3) {
            try session.perform(MoveRegions(screen: screen.id, regions: everything, dx: 8, dy: 0))
            try session.undo()
        }
        XCTAssertLessThan(moveAll, 1500)
    }

    /// Select all and nudge one point, and select all and drop a drag, at 2,000 and 5,000 regions. Each is performed
    /// and undone.
    func testNudgeAndDropOfEverythingWithinBudget() throws {
        for count in [2000, 5000] {
            let project = Project.stressTest(regionCount: count)
            let screen = try XCTUnwrap(project.screens.first)
            let session = EditSession(project: project)
            let everything = screen.allRegions.map(\.id)
            let nudge = try time("perform and undo a select-all nudge", regions: count, iterations: 5) {
                try session.perform(MoveRegions(screen: screen.id, regions: everything, dx: 1, dy: 0))
                try session.undo()
            }

            let target = try XCTUnwrap(screen.allRegions.first { $0.children.isEmpty && $0.frame.w >= 8 })
            let press = CGPoint(x: Double(target.frame.x) + 4, y: Double(target.frame.y) + 4)
            let context = GestureContext(screen: screen, tool: .select, selection: everything)
            var gesture = CanvasGesture(pressAt: press, context: context)
            gesture.drag(to: CGPoint(x: press.x + 40, y: press.y + 24))
            let drop = try XCTUnwrap(gesture.release(at: CGPoint(x: press.x + 40, y: press.y + 24)))
            let dropTime = try time("perform and undo dropping a select-all drag", regions: count, iterations: 5) {
                try session.perform(drop)
                try session.undo()
            }
            XCTAssertLessThan(nudge, 1500)
            XCTAssertLessThan(dropTime, 1500)
        }
    }

    /// What the details panel does on each keystroke: finding the open region, on the first and on the last of 40
    /// screens of 300 regions.
    func testRegionLookupOnTheLastOfFortyScreensWithinBudget() throws {
        let project = Project.stressTest(regionCount: 300, screenCount: 40)
        let first = try XCTUnwrap(project.screens.first)
        let last = try XCTUnwrap(project.screens.last)
        let firstRegion = try XCTUnwrap(first.allRegions.last).id
        let lastRegion = try XCTUnwrap(last.allRegions.last).id
        let onFirst = time("find a region on the first of 40 screens", regions: 12000, iterations: 200) {
            _ = project.region(withID: firstRegion)
        }
        let onLast = time("find a region on the last of 40 screens", regions: 12000, iterations: 200) {
            _ = project.region(withID: lastRegion)
        }
        let onLastWithScreen = time(
            "find a region on the last of 40 screens, given the screen", regions: 12000, iterations: 200
        ) {
            _ = project.region(withID: lastRegion, onScreen: last.id)
        }
        XCTAssertLessThan(onFirst, 50)
        XCTAssertLessThan(onLast, 50)
        XCTAssertLessThan(onLastWithScreen, 50)
    }
}
