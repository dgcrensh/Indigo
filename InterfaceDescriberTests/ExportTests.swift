import AppKit
import DescriberCore
import XCTest

@testable import InterfaceDescriber

/// Rendering screens to PNG and the File > Export items (milestone 11).
final class ExportTests: XCTestCase {
    /// The pixels of an image as RGBA bytes, with rows from the top. Points are screen points: the image's top-left
    /// corner is the extent's.
    private struct Pixels {
        let width: Int
        let height: Int
        let scale: Int
        let origin: (x: Int, y: Int)
        let bytes: [UInt8]

        init(_ image: CGImage, scale: Int, extent: Frame) throws {
            width = image.width
            height = image.height
            self.scale = scale
            origin = (extent.x, extent.y)
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
            let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
                guard
                    let context = CGContext(
                        data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                        bytesPerRow: image.width * 4, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                else { return false }
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                return true
            }
            XCTAssertTrue(drawn)
            self.bytes = bytes
        }

        /// The color at a point in screen points.
        func color(x: Int, y: Int) -> [UInt8] {
            let offset = (((y - origin.y) * scale) * width + (x - origin.x) * scale) * 4
            return Array(bytes[offset..<offset + 3])
        }

        /// How many pixels in a rectangle of screen points are darker than `threshold` (0 to 255).
        func darkCount(in screenFrame: Frame, threshold: Int = 160) -> Int {
            let frame = screenFrame.offsetBy(dx: -origin.x, dy: -origin.y)
            var count = 0
            for y in frame.y * scale..<frame.maxY * scale {
                for x in frame.x * scale..<frame.maxX * scale {
                    let offset = (y * width + x) * 4
                    let luma = (Int(bytes[offset]) * 3 + Int(bytes[offset + 1]) * 6 + Int(bytes[offset + 2])) / 10
                    if luma < threshold { count += 1 }
                }
            }
            return count
        }
    }

    private let regionID = RegionID("region")
    private let listID = RegionID("list")
    private let rowID = RegionID("row")

    /// A 200 × 500 screen with a tall region holding a description, and a list scrolling vertically whose row is
    /// below the fold:
    ///
    ///     region  (20, 20, 160 × 60)
    ///     list    (0, 100, 200 × 200), content 200 × 600
    ///       row   (10, 400, 180 × 40)
    private func makeProject() -> (Project, Screen) {
        let region = Region(
            id: regionID, title: "Header", frame: Frame(x: 20, y: 20, w: 160, h: 60),
            description: "Shown with D. Wraps onto a second line inside the region.")
        let row = Region(id: rowID, title: "Row title", frame: Frame(x: 10, y: 400, w: 180, h: 40))
        let list = Region(
            id: listID, title: "List", frame: Frame(x: 0, y: 100, w: 200, h: 200),
            scroll: Scroll(axis: .vertical, contentWidth: 200, contentHeight: 600), children: [row])
        let screen = Screen(name: "Home", viewport: Viewport(width: 200, height: 500), regions: [region, list])
        return (Project(name: "Test", screens: [screen]), screen)
    }

    @MainActor
    private func render(_ screen: Screen, in project: Project, scale: Int = 1) throws -> Pixels {
        let image = try XCTUnwrap(ScreenImageRenderer.image(for: screen, in: project, scale: scale))
        let offsets = project.editorState.screens[screen.id]?.scrollOffsets ?? [:]
        return try Pixels(image, scale: scale, extent: ScreenImage.extent(of: screen, offsets: offsets))
    }

    /// Whether two colors are the same to within `tolerance` in each channel.
    private func assertColor(
        _ color: [UInt8], is expected: PaperColor, tolerance: Int = 2, _ message: String = "",
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let wanted = [expected.red, expected.green, expected.blue].map { Int(($0 * 255).rounded()) }
        for (got, want) in zip(color.map(Int.init), wanted) where abs(got - want) > tolerance {
            XCTFail("\(color) is not \(wanted) \(message)", file: file, line: line)
            return
        }
    }

    @MainActor
    func testTheImageIsTheScreensAreaTimesTheScale() throws {
        let (project, screen) = makeProject()
        // The screen, with room for the sheet's shadow on every side.
        let single = try render(screen, in: project, scale: 1)
        XCTAssertEqual([single.width, single.height], [232, 532])
        let double = try render(screen, in: project, scale: 2)
        XCTAssertEqual([double.width, double.height], [464, 1064])

        // A region past the right edge widens the image, and its outside part is tinted.
        screen.regions.append(Region(title: "Wide", frame: Frame(x: 150, y: 400, w: 100, h: 50)))
        let wide = try render(screen, in: project)
        XCTAssertEqual([wide.width, wide.height], [266, 532])
        XCTAssertNotEqual(wide.color(x: 230, y: 440), wide.color(x: 170, y: 440), "the part outside is tinted")
        XCTAssertNotEqual(wide.color(x: 230, y: 480), wide.color(x: 170, y: 480), "the background is not the bounds")
    }

    @MainActor
    func testRegionsAreFilledAndTitlesDrawAtTheTop() throws {
        let (project, screen) = makeProject()
        let pixels = try render(screen, in: project, scale: 2)
        XCTAssertNotEqual(pixels.color(x: 100, y: 60), pixels.color(x: 100, y: 90), "the region has a fill")
        let titleBand = Frame(x: 24, y: 22, w: 100, h: 14)
        let bottomBand = Frame(x: 24, y: 62, w: 150, h: 14)
        XCTAssertGreaterThan(pixels.darkCount(in: titleBand), 20, "the title is at the top of the region")
        XCTAssertEqual(pixels.darkCount(in: bottomBand), 0, "nothing is drawn at the bottom of the region")
    }

    @MainActor
    func testDescriptionsShowOnlyForRegionsShowingThem() throws {
        let (project, screen) = makeProject()
        let band = Frame(x: 24, y: 40, w: 150, h: 36)
        let hidden = try render(screen, in: project, scale: 2)
        XCTAssertEqual(hidden.darkCount(in: band, threshold: 220), 0)
        project.editorState.visibleDescriptions = [regionID]
        let shown = try render(screen, in: project, scale: 2)
        XCTAssertGreaterThan(shown.darkCount(in: band, threshold: 220), 20)
    }

    @MainActor
    func testContentScrolledOutOfViewIsClipped() throws {
        let (project, screen) = makeProject()
        let below = try render(screen, in: project)
        // Under the list, where the row would be without clipping, is plain bounds.
        XCTAssertEqual(below.color(x: 100, y: 420), below.color(x: 100, y: 480))
        XCTAssertEqual(below.darkCount(in: Frame(x: 14, y: 402, w: 100, h: 14)), 0)

        project.editorState.screens[screen.id] = ScreenEditorState(scrollOffsets: [listID: ScrollOffset(x: 0, y: 250)])
        let scrolled = try render(screen, in: project, scale: 2)
        // Scrolled by 250, the row shows at y 150 inside the list.
        XCTAssertGreaterThan(scrolled.darkCount(in: Frame(x: 14, y: 152, w: 100, h: 14)), 20)
        XCTAssertEqual(scrolled.color(x: 100, y: 420), scrolled.color(x: 100, y: 480))
    }

    @MainActor
    func testImagesUseTheLightPaperLookInEitherAppearance() throws {
        let (project, screen) = makeProject()
        let button = Region(title: "Go", kind: .button, frame: Frame(x: 20, y: 420, w: 160, h: 60))
        screen.regions.append(button)
        let previous = NSApp.appearance
        defer { NSApp.appearance = previous }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            NSApp.appearance = NSAppearance(named: appearance)
            let pixels = try render(screen, in: project, scale: 2)
            let light = PaperPalette.light
            assertColor(pixels.color(x: -16, y: -16), is: light.desk, "the corner is desk, \(appearance.rawValue)")
            assertColor(pixels.color(x: 100, y: 330), is: light.sheet, "the middle is sheet, \(appearance.rawValue)")
            assertColor(
                pixels.color(x: 100, y: 465), is: light.colors(for: .button).fill,
                "a button is the action fill, \(appearance.rawValue)")
            // Just under the sheet's bottom edge, the shadow darkens the desk.
            XCTAssertLessThan(
                Int(pixels.color(x: 100, y: 503)[0]), Int((light.desk.red * 255).rounded()) - 2, "the shadow is drawn")
        }
    }

    @MainActor
    func testTheFileMenuHasTheExports() throws {
        let file = try XCTUnwrap(MainMenu.make().items.first { $0.title == "File" }?.submenu)
        let export = try XCTUnwrap(file.items.first { $0.title == "Export" }?.submenu)
        XCTAssertEqual(
            export.items.map(\.title), ["Markdown…", "Single-File JSON…", "PNG Images…"])
        XCTAssertEqual(
            export.items.map(\.action),
            [
                #selector(DocumentWindowController.exportMarkdown(_:)),
                #selector(DocumentWindowController.exportJSON(_:)),
                #selector(DocumentWindowController.exportPNGs(_:)),
            ])
    }

    @MainActor
    func testTheWritersWriteTheCoresExportsAndOnePNGPerScreen() throws {
        let document = Document()
        document.makeWindowControllers()
        let controller = try XCTUnwrap(document.windowControllers.first as? DocumentWindowController)
        defer { controller.close() }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        document.fileURL = folder.appendingPathComponent("Acme.uidesc")

        let export = controller.exportController
        XCTAssertEqual(export.documentName, "Acme")
        let project = document.model.project
        project.screens.append(Screen(name: "Screen 1", kind: .menu, viewport: Viewport(width: 240, height: 136)))

        let markdownURL = folder.appendingPathComponent("Acme.md")
        try export.writeMarkdown(to: markdownURL)
        XCTAssertEqual(
            try String(contentsOf: markdownURL, encoding: .utf8), MarkdownExport.markdown(for: project, title: "Acme"))
        let jsonURL = folder.appendingPathComponent("Acme.json")
        try export.writeJSON(to: jsonURL)
        XCTAssertEqual(try Data(contentsOf: jsonURL), ProjectJSONExport.data(for: project))

        let urls = try export.writePNGs(to: folder, scale: 2)
        XCTAssertEqual(urls.map(\.lastPathComponent), ["screen-1@2x.png", "screen-1-2@2x.png"])
        let menu = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: urls[1])))
        XCTAssertEqual([menu.pixelsWide, menu.pixelsHigh], [544, 336])
        XCTAssertEqual(menu.size, NSSize(width: 272, height: 168))
    }
}
