import XCTest

@testable import DescriberCore

final class ProjectEncodingTests: XCTestCase {
    private func keys(_ value: JSONValue) -> [String] {
        guard case .object(let pairs) = value else { return [] }
        return pairs.map(\.key)
    }

    func testOpenRegionWithNothingOptionalWritesOnlyRequiredKeys() {
        let (project, _) = Fixtures.simpleProject()
        let region = Region(id: RegionID("r1"), title: "Plain", frame: Frame(x: 1, y: 2, w: 30, h: 40))
        XCTAssertEqual(
            keys(ProjectEncoding.region(region, in: project)), ["id", "title", "x", "y", "w", "h", "description"])
    }

    func testRegionKeysFollowTheSpecOrder() {
        let (project, screen) = Fixtures.simpleProject()
        let child = Region(id: RegionID("c"), title: "Child", frame: Frame(x: 0, y: 0, w: 10, h: 10))
        let region = Region(
            id: RegionID("r"),
            title: "Full",
            kind: .list,
            frame: Frame(x: 0, y: 0, w: 100, h: 100),
            description: "Every field",
            scroll: Scroll(axis: .vertical, contentWidth: 100, contentHeight: 300),
            links: [Link(screen: screen.id, trigger: "click")],
            children: [child]
        )
        XCTAssertEqual(
            keys(ProjectEncoding.region(region, in: project)),
            ["id", "title", "kind", "x", "y", "w", "h", "description", "scroll", "linksTo", "children"]
        )
    }

    func testScreenKeysFollowTheSpecOrder() {
        let (project, screen) = Fixtures.simpleProject()
        XCTAssertEqual(
            keys(ProjectEncoding.screen(screen, in: project)), ["id", "name", "kind", "viewport", "regions"])
        screen.scroll = Scroll(axis: .both, contentWidth: 800, contentHeight: 1600)
        XCTAssertEqual(
            keys(ProjectEncoding.screen(screen, in: project)),
            ["id", "name", "kind", "viewport", "scroll", "regions"]
        )
    }

    func testManifestKeysFollowTheSpecOrderAndOmitEmptyVariantGroups() {
        let (project, screen) = Fixtures.simpleProject()
        let files = ProjectPackage.screenFiles(for: project)
        XCTAssertEqual(
            keys(ProjectEncoding.manifest(project, files: files)), ["schemaVersion", "name", "units", "screens"])
        project.variantGroups = [VariantGroup(name: "Home", screens: [screen.id])]
        XCTAssertEqual(
            keys(ProjectEncoding.manifest(project, files: files)),
            ["schemaVersion", "name", "units", "screens", "variantGroups"]
        )
    }

    func testViewportWithoutPresetOmitsIt() {
        let (project, screen) = Fixtures.simpleProject()
        screen.viewport = Viewport(width: 240, height: 180)
        let text = OrderedJSONWriter.string(ProjectEncoding.screen(screen, in: project))
        XCTAssertTrue(text.contains("\"viewport\": {\n    \"width\": 240,\n    \"height\": 180\n  }"), text)
    }

    func testLinkWithoutTriggerOmitsIt() {
        let (project, screen) = Fixtures.simpleProject()
        let region = Region(
            id: RegionID("r"),
            title: "Link",
            frame: Frame(x: 0, y: 0, w: 10, h: 10),
            links: [Link(screen: screen.id)]
        )
        guard case .object(let pairs) = ProjectEncoding.region(region, in: project),
            case .array(let links)? = pairs.first(where: { $0.key == "linksTo" })?.value
        else { return XCTFail("no linksTo") }
        XCTAssertEqual(links.map(keys), [["screen", "screenName"]])
    }

    func testDerivedFieldsFollowARename() throws {
        let project = AcmeExample.make()
        let before = ProjectPackage.write(project: project)
        let reset = try XCTUnwrap(project.screen(withID: AcmeExample.resetPassword))
        reset.name = "Recover Account"

        let after = ProjectPackage.write(project: project, previous: before.tree)
        let manifest = Fixtures.string(after.tree["project.json"])
        XCTAssertTrue(
            manifest.contains("\"name\": \"Recover Account\",\n      \"file\": \"screens/recover-account.json\""))
        XCTAssertFalse(manifest.contains("Reset Password"))
        for (path, data) in after.tree where path.hasPrefix("screens/") {
            let text = Fixtures.string(data)
            XCTAssertFalse(text.contains("\"screenName\": \"Reset Password\""), path)
        }
        XCTAssertTrue(Fixtures.string(after.tree["screens/login.json"]).contains("\"screenName\": \"Recover Account\""))
        XCTAssertEqual(after.removed, ["screens/reset-password.json"])
    }

    func testEditorStateIsWrittenWithSortedKeysAndReadBack() throws {
        let (project, screen) = Fixtures.simpleProject()
        let region = RegionID("00000000-0000-4000-8000-0000000000aa")
        project.editorState = EditorState(
            screens: [
                screen.id: ScreenEditorState(
                    zoom: 1.5, panX: -20, panY: 10.25, gridSize: 8, scrollOffsets: [region: ScrollOffset(x: 0, y: 120)])
            ],
            visibleDescriptions: [region],
            lastActiveScreen: screen.id
        )
        let written = ProjectPackage.write(project: project)
        let data = try XCTUnwrap(written.tree[".editor-state.json"])
        let reread = try ProjectPackage.read(written.tree)
        XCTAssertEqual(reread.editorState, project.editorState)
        XCTAssertEqual(OrderedJSONWriter.data(ProjectEncoding.editorState(reread.editorState)), data)
    }
}
