import XCTest

@testable import DescriberCore

/// The sidebar's screen thumbnails (milestone 14).
final class ScreenThumbnailTests: XCTestCase {
    func testTheSheetKeepsItsAspectAndIsCentered() {
        let center = Region(title: "Center", kind: .button, frame: Frame(x: 186, y: 416, w: 20, h: 20))
        let screen = Screen(name: "Login", viewport: .defaultForNewScreens, regions: [center])
        let thumbnail = ScreenThumbnail.rects(for: screen, width: 40, height: 72)
        XCTAssertEqual(thumbnail.sheet.w, 33.2, accuracy: 0.05)
        XCTAssertEqual(thumbnail.sheet.h, 72, accuracy: 0.001)
        XCTAssertEqual(thumbnail.sheet.x, (40 - thumbnail.sheet.w) / 2, accuracy: 0.001)
        XCTAssertEqual(thumbnail.sheet.y, 0, accuracy: 0.001)
        XCTAssertEqual(thumbnail.sheetRadius, 55 * 72 / 852, accuracy: 0.001)
        let region = thumbnail.regions[0]
        XCTAssertEqual(region.family, .action)
        XCTAssertEqual(region.frame.x + region.frame.w / 2, 20, accuracy: 0.05)
        XCTAssertEqual(region.frame.y + region.frame.h / 2, 36, accuracy: 0.05)
    }

    func testRegionsAreBackToFront() {
        let (_, screen, _, _, _) = Fixtures.nestedProject()
        let thumbnail = ScreenThumbnail.rects(for: screen, width: 40, height: 80)
        // Outer, then Inner inside it, then Side, as the canvas draws them; 0.1 pt per screen point.
        XCTAssertEqual(
            thumbnail.regions.map(\.frame),
            [
                ThumbnailRect(x: 0, y: 0, w: 20, h: 20), ThumbnailRect(x: 2, y: 2, w: 10, h: 10),
                ThumbnailRect(x: 30, y: 0, w: 10, h: 10),
            ])
    }

    func testScrolledContentIsClippedToItsParent() {
        let row = Region(title: "Row", frame: Frame(x: 0, y: 150, w: 100, h: 100))
        let list = Region(
            title: "List", frame: Frame(x: 0, y: 0, w: 100, h: 200),
            scroll: Scroll(axis: .vertical, contentWidth: 100, contentHeight: 600), children: [row])
        let below = Region(title: "Below", frame: Frame(x: 0, y: 500, w: 100, h: 100))
        list.children.append(below)
        let screen = Screen(name: "S", viewport: Viewport(width: 100, height: 800), regions: [list])
        let thumbnail = ScreenThumbnail.rects(for: screen, width: 10, height: 80)
        XCTAssertEqual(
            thumbnail.regions.map(\.frame),
            [ThumbnailRect(x: 0, y: 0, w: 10, h: 20), ThumbnailRect(x: 0, y: 15, w: 10, h: 5)],
            "the row is cut at the list's bottom, and the region scrolled out of view is left out")
    }

    func testTinyRegionsAreDropped() {
        let dot = Region(title: "Dot", frame: Frame(x: 10, y: 10, w: 2, h: 2))
        let bar = Region(title: "Bar", frame: Frame(x: 10, y: 10, w: 400, h: 40))
        let screen = Screen(
            name: "Desk", viewport: Viewport(preset: "desktop", width: 1920, height: 1080), regions: [dot, bar])
        let thumbnail = ScreenThumbnail.rects(for: screen, width: 40, height: 72)
        XCTAssertEqual(thumbnail.regions.count, 1)
        XCTAssertEqual(thumbnail.sheetRadius, 0)
        XCTAssertEqual(thumbnail.sheet.w, 40, accuracy: 0.001, "a wide screen is short and wide in the same box")
    }

    func testABusyScreenKeepsTheTopmostRegionsCheaply() throws {
        let screen = try XCTUnwrap(Project.stressTest(regionCount: 500).screens.first)
        let all = screen.allRegions
        // The best of five runs, so a busy machine doesn't fail the budget.
        var elapsed = Double.infinity
        var thumbnail = ScreenThumbnail.rects(for: screen, width: 40, height: 72)
        for _ in 0..<5 {
            let start = Date()
            thumbnail = ScreenThumbnail.rects(for: screen, width: 40, height: 72)
            elapsed = min(elapsed, Date().timeIntervalSince(start))
        }
        XCTAssertLessThanOrEqual(thumbnail.regions.count, ScreenThumbnail.maximumRegions)
        let layout = ScrollLayout(screen: screen)
        let scale = min(40 / Double(screen.canvasBounds.w), 72 / Double(screen.canvasBounds.h))
        let shown = all.filter {
            guard let frame = layout.visibleFrame(of: $0.id) else { return false }
            return Double(frame.w) * scale >= 0.5 && Double(frame.h) * scale >= 0.5
        }
        XCTAssertEqual(thumbnail.regions.map(\.family), shown.suffix(300).map(\.kind.family), "the topmost are kept")
        XCTAssertLessThan(elapsed, 0.002, "under 2 ms")
    }
}

final class ThumbnailFingerprintTests: XCTestCase {
    func testOnlyWhatTheThumbnailDrawsChangesIt() {
        let (_, screen, _, inner, _) = Fixtures.nestedProject()
        let start = ScreenThumbnail.fingerprint(of: screen)
        inner.title = "Renamed"
        inner.description = "Words"
        XCTAssertEqual(ScreenThumbnail.fingerprint(of: screen), start)
        inner.kind = .button
        let kinded = ScreenThumbnail.fingerprint(of: screen)
        XCTAssertNotEqual(kinded, start)
        inner.frame = inner.frame.offsetBy(dx: 1, dy: 0)
        XCTAssertNotEqual(ScreenThumbnail.fingerprint(of: screen), kinded)
    }
}

final class SidebarDetailTests: XCTestCase {
    func testCardsNameTheViewportAndAnOverlaysKind() {
        XCTAssertEqual(Screen(name: "Login", viewport: .defaultForNewScreens).sidebarDetail(), "iPhone 15")
        XCTAssertEqual(Screen(name: "C", viewport: Viewport(width: 500, height: 400)).sidebarDetail(), "500 × 400")
        let menu = Screen(name: "Account", kind: .menu, viewport: Viewport(width: 240, height: 180))
        XCTAssertEqual(menu.sidebarDetail(), "Menu · 240 × 180")
    }
}
