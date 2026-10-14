import XCTest

@testable import DescriberCore

/// The Markdown, single-file JSON and PNG naming exports (milestone 11).
final class MarkdownExportTests: XCTestCase {
    func testAnchorsFollowGitHubsHeadingIDs() {
        XCTAssertEqual(MarkdownText.anchorBase("Login"), "login")
        XCTAssertEqual(MarkdownText.anchorBase("Login (Desktop)"), "login-desktop")
        XCTAssertEqual(MarkdownText.anchorBase("Sign in / Sign up"), "sign-in--sign-up")
        XCTAssertEqual(MarkdownText.anchorBase("Café Menü"), "café-menü")
        XCTAssertEqual(MarkdownText.anchorBase("user_profile-2"), "user_profile-2")
        XCTAssertEqual(MarkdownText.anchorBase("What's new? ✨"), "whats-new-")
    }

    func testRepeatedHeadingsAreNumbered() {
        var anchors = MarkdownText.Anchors()
        XCTAssertEqual(anchors.next(for: "Home"), "home")
        XCTAssertEqual(anchors.next(for: "Home"), "home-1")
        XCTAssertEqual(anchors.next(for: "Home-1"), "home-1-1")
        XCTAssertEqual(anchors.next(for: "HOME"), "home-2")
    }

    func testEscapingShowsTextAsTyped() {
        XCTAssertEqual(
            MarkdownText.escaped("*Bold* [link] <tag> a_b `x` #1 | \\"),
            "\\*Bold\\* \\[link\\] \\<tag\\> a\\_b \\`x\\` \\#1 \\| \\\\")
        XCTAssertEqual(MarkdownText.escaped("Two\nlines"), "Two lines")
    }

    func testEveryLinkInTheExampleExportPointsAtAHeading() throws {
        let markdown = MarkdownExport.markdown(for: AcmeExample.make())
        var anchors = MarkdownText.Anchors()
        var headings = Set<String>()
        for line in markdown.split(separator: "\n") where line.hasPrefix("#") {
            headings.insert(anchors.next(for: String(line.drop { $0 == "#" }.dropFirst())))
        }
        let targets = markdown.matches(of: #/\]\(#([^)]+)\)/#).map { String($0.output.1) }
        XCTAssertEqual(targets.count, 15)
        for target in targets {
            XCTAssertTrue(headings.contains(target), "#\(target) is not a heading")
        }
    }

    func testTheTitleCountsBeforeScreensOfTheSameName() {
        let home = Screen(name: "Home", viewport: Viewport(width: 100, height: 100))
        let other = Screen(
            name: "Other", viewport: Viewport(width: 100, height: 100),
            regions: [Region(title: "Back", frame: Frame(x: 0, y: 0, w: 10, h: 10), links: [Link(screen: home.id)])])
        let markdown = MarkdownExport.markdown(for: Project(name: "Home", screens: [home, other]))
        XCTAssertTrue(markdown.contains("- [Home](#home-1)\n- [Other](#other)\n"))
        XCTAssertTrue(markdown.contains("Links to [Home](#home-1)."))
    }

    func testRegionLines() {
        let missing = ScreenID("00000000-0000-4000-8000-00000000dead")
        let target = Screen(name: "Detail *new*", viewport: Viewport(width: 100, height: 100))
        let child = Region(title: "Child", kind: .button, frame: Frame(x: 4, y: 8, w: 20, h: 10))
        let region = Region(
            title: "List [main]", frame: Frame(x: 0, y: 0, w: 100, h: 50),
            description: "First line.\n\nSecond paragraph.\n",
            scroll: Scroll(axis: .both, contentWidth: 200, contentHeight: 300),
            links: [Link(screen: target.id, trigger: "click"), Link(screen: missing, trigger: "")],
            children: [child])
        let untitled = Region(title: "", frame: Frame(x: 0, y: 60, w: 10, h: 10))
        let screen = Screen(
            name: "Home", viewport: Viewport(width: 100, height: 100), regions: [region, untitled])
        let markdown = MarkdownExport.markdown(for: Project(name: "P", screens: [screen, target]))
        XCTAssertTrue(
            markdown.contains(
                """
                Regions:

                - **List \\[main\\]**: x 0, y 0, 100 × 50.
                  First line.

                  Second paragraph.
                  Scrolls in both directions, content 200 × 300.
                  Links to [Detail \\*new\\*](#detail-new) (click); a missing screen (`00000000-0000-4000-8000-00000000dead`).
                  - **Child** (button): x 4, y 8, 20 × 10.
                - **(untitled)**: x 0, y 60, 10 × 10.

                ## Detail \\*new\\*

                - Kind: screen
                - Viewport: Custom, 100 × 100

                No regions.

                """), markdown)
    }

    func testScreenDetails() {
        let screen = Screen(
            name: "Feed", kind: .sheet, viewport: ViewportPresets.thisDevice(width: 1512, height: 982),
            scroll: Scroll(axis: .vertical, contentWidth: 1512, contentHeight: 3000))
        let custom = Screen(name: "Watch", viewport: Viewport(preset: "watch", width: 198, height: 242))
        let lone = Screen(name: "Lone", viewport: Viewport(width: 10, height: 10))
        let project = Project(
            name: "P", screens: [screen, custom, lone],
            variantGroups: [
                VariantGroup(name: "Feed", screens: [screen.id, custom.id]),
                VariantGroup(name: "Alone", screens: [lone.id]),
            ])
        let markdown = MarkdownExport.markdown(for: project)
        XCTAssertTrue(
            markdown.contains(
                """
                ## Feed

                - Kind: sheet
                - Viewport: This Device, 1512 × 982
                - Scrolls vertically, content 1512 × 3000
                - Variants (Feed): [Watch](#watch)

                """), markdown)
        XCTAssertTrue(markdown.contains("- Viewport: watch, 198 × 242\n- Variants (Feed): [Feed](#feed)\n"))
        XCTAssertTrue(markdown.contains("## Lone\n\n- Kind: screen\n- Viewport: Custom, 10 × 10\n\nNo regions.\n"))
        XCTAssertTrue(markdown.hasPrefix("# P\n\n3 screens."))
    }

    func testTitleDefaultsToTheProjectName() {
        let (project, _) = Fixtures.simpleProject()
        XCTAssertTrue(MarkdownExport.markdown(for: project).hasPrefix("# Test\n\n1 screen. "))
        XCTAssertTrue(MarkdownExport.markdown(for: project, title: "My App").hasPrefix("# My App\n"))
    }
}

final class ProjectJSONExportTests: XCTestCase {
    func testEachScreenIsWrittenAsItsScreenFileIs() throws {
        let project = AcmeExample.make()
        guard case .object(let pairs) = ProjectJSONExport.json(for: project) else {
            return XCTFail("The export is not an object")
        }
        XCTAssertEqual(pairs.map(\.key), ["schemaVersion", "name", "units", "screens", "variantGroups"])
        guard case .array(let screens) = pairs[3].value else { return XCTFail("screens is not an array") }
        XCTAssertEqual(screens, project.screens.map { ProjectEncoding.screen($0, in: project) })

        let tree = try Fixtures.readTree(at: Fixtures.examplePackage)
        let exported = Fixtures.string(ProjectJSONExport.data(for: project))
        for path in tree.keys where path.hasPrefix("screens/") {
            // Each screen file, indented two levels, appears in the export as is.
            let indented = Fixtures.string(tree[path]).split(separator: "\n").map { "    " + $0 }
            XCTAssertTrue(exported.contains(indented.joined(separator: "\n").dropFirst(4)), path)
        }
        XCTAssertFalse(exported.contains("\"file\""))
        XCTAssertFalse(exported.contains("zoom"))
    }

    func testNoVariantGroupsKeyWhenThereAreNone() {
        let (project, _) = Fixtures.simpleProject()
        guard case .object(let pairs) = ProjectJSONExport.json(for: project) else {
            return XCTFail("The export is not an object")
        }
        XCTAssertEqual(pairs.map(\.key), ["schemaVersion", "name", "units", "screens"])
    }

    func testSchemaRejectsAManifestEntryInTheExport() throws {
        let validator = try SchemaValidator(schema: Data(contentsOf: Fixtures.schema))
        let (project, _) = Fixtures.simpleProject()
        let exported = Fixtures.string(ProjectJSONExport.data(for: project))
        XCTAssertEqual(try validator.validate(Data(exported.utf8)).count, 0)
        let manifestStyle = exported.replacingOccurrences(
            of: "\"name\": \"Home\",", with: "\"name\": \"Home\",\n\"file\": \"screens/home.json\",")
        XCTAssertNotEqual(manifestStyle, exported)
        XCTAssertFalse(try validator.validate(Data(manifestStyle.utf8)).isEmpty)
    }
}

final class ScreenImageTests: XCTestCase {
    func testAScreenWhoseRegionsFitIsItsCanvasBounds() {
        let (_, screen, _, _, _) = Fixtures.nestedProject()
        XCTAssertEqual(ScreenImage.extent(of: screen), Frame(x: 0, y: 0, w: 400, h: 800))
        screen.scroll = Scroll(axis: .vertical, contentWidth: 400, contentHeight: 1200)
        XCTAssertEqual(ScreenImage.extent(of: screen), Frame(x: 0, y: 0, w: 400, h: 1200))
    }

    func testRegionsOutsideTheBoundsWidenIt() {
        let (_, screen, _, _, side) = Fixtures.nestedProject()
        side.frame = Frame(x: 350, y: -20, w: 100, h: 100)
        XCTAssertEqual(ScreenImage.extent(of: screen), Frame(x: 0, y: -20, w: 450, h: 820))
    }

    func testContentScrolledOutOfViewDoesNotWidenIt() {
        let row = Region(id: RegionID("row"), title: "Row", frame: Frame(x: 0, y: 700, w: 100, h: 40))
        let list = Region(
            id: RegionID("list"), title: "List", frame: Frame(x: 0, y: 600, w: 100, h: 200),
            scroll: Scroll(axis: .vertical, contentWidth: 100, contentHeight: 900), children: [row])
        let screen = Screen(name: "S", viewport: Viewport(width: 100, height: 800), regions: [list])
        row.frame = Frame(x: 0, y: 1400, w: 100, h: 40)
        XCTAssertEqual(ScreenImage.extent(of: screen), Frame(x: 0, y: 0, w: 100, h: 800))
        // Scrolled so the row shows inside the list, which is inside the bounds.
        XCTAssertEqual(
            ScreenImage.extent(of: screen, offsets: [list.id: ScrollOffset(x: 0, y: 700)]),
            Frame(x: 0, y: 0, w: 100, h: 800))
    }

    func testFileNamesAreScreenSlugs() {
        let project = AcmeExample.make()
        project.screens.append(Screen(name: "Login", viewport: Viewport(width: 10, height: 10)))
        let names = ScreenImage.fileNames(for: project, scale: 1)
        XCTAssertEqual(
            project.screens.map { names[$0.id]! },
            [
                "login.png", "login-desktop.png", "reset-password.png", "settings.png", "account-menu.png",
                "login-2.png",
            ])
        let retina = ScreenImage.fileNames(for: project, scale: 2)
        XCTAssertEqual(retina[AcmeExample.login], "login@2x.png")
    }
}
