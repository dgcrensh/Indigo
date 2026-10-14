import XCTest

@testable import DescriberCore

final class ProjectDecodingTests: XCTestCase {
    private let screenID = "00000000-0000-4000-8000-000000000001"
    private let otherID = "00000000-0000-4000-8000-000000000002"

    private func manifest(version: String = "1", screens: String? = nil, extra: String = "") -> Data {
        let entries = screens ?? "[{ \"id\": \"\(screenID)\", \"name\": \"Home\", \"file\": \"screens/home.json\" }]"
        return Data(
            "{ \"schemaVersion\": \(version), \"name\": \"T\", \"units\": \"points\", \"screens\": \(entries)\(extra) }"
                .utf8)
    }

    private func screen(id: String? = nil, kind: String = "screen", regions: String = "[]") -> Data {
        Data(
            """
            { "id": "\(id ?? screenID)", "name": "Home", "kind": "\(kind)",
              "viewport": { "width": 393, "height": 852 }, "regions": \(regions) }
            """.utf8
        )
    }

    private func region(_ id: String, kind: String? = nil, links: String? = nil, children: String? = nil) -> String {
        var fields = "\"id\": \"\(id)\", \"title\": \"R\", \"x\": 0, \"y\": 0, \"w\": 10, \"h\": 10"
        if let kind { fields += ", \"kind\": \"\(kind)\"" }
        if let links { fields += ", \"linksTo\": \(links)" }
        if let children { fields += ", \"children\": \(children)" }
        return "{ \(fields) }"
    }

    private func read(_ tree: PackageTree) -> Result<Project, FormatError> {
        Result {
            try ProjectPackage.read(tree)
        }
        .mapError { $0 as! FormatError }
    }

    private func assertError(_ tree: PackageTree, _ expected: FormatError, line: UInt = #line) {
        switch read(tree) {
        case .success: XCTFail("expected \(expected)", line: line)
        case .failure(let error):
            XCTAssertEqual(error, expected, line: line)
            XCTAssertNotNil(error.errorDescription, line: line)
        }
    }

    func testReadsAMinimalPackage() throws {
        let project = try ProjectPackage.read(["project.json": manifest(), "screens/home.json": screen()])
        XCTAssertEqual(project.name, "T")
        XCTAssertEqual(project.screens.map(\.name), ["Home"])
        XCTAssertEqual(project.editorState, EditorState())
    }

    func testMissingManifest() {
        assertError(["screens/home.json": screen()], .missingManifest)
    }

    func testUnsupportedSchemaVersionIsCheckedBeforeAnyScreenFileIsRead() {
        var requested: [String] = []
        XCTAssertThrowsError(
            try ProjectPackage.read { path in
                requested.append(path)
                return path == "project.json" ? self.manifest(version: "2") : Data("not json".utf8)
            }
        ) { error in
            XCTAssertEqual(error as? FormatError, .unsupportedSchemaVersion(found: 2))
        }
        XCTAssertEqual(requested, ["project.json"])
    }

    func testMissingSchemaVersionIsUnsupported() {
        let data = Data("{ \"name\": \"T\", \"screens\": [] }".utf8)
        assertError(["project.json": data], .unsupportedSchemaVersion(found: nil))
    }

    func testMalformedManifest() {
        assertError(
            ["project.json": Data("{ nope".utf8)], .malformedJSON(file: "project.json", detail: "not valid JSON"))
    }

    func testMalformedScreenFileNamesTheFileAndThePath() {
        let bad = Data("{ \"id\": \"\(screenID)\", \"name\": \"Home\", \"kind\": \"screen\", \"regions\": [] }".utf8)
        assertError(
            ["project.json": manifest(), "screens/home.json": bad],
            .malformedJSON(file: "screens/home.json", detail: "missing \"viewport\"")
        )
        let badRegion = screen(regions: "[{ \"id\": \"r\", \"title\": \"R\", \"x\": 0, \"y\": 0, \"w\": 10 }]")
        assertError(
            ["project.json": manifest(), "screens/home.json": badRegion],
            .malformedJSON(file: "screens/home.json", detail: "missing \"h\" in regions[0]")
        )
    }

    func testMissingScreenFile() {
        assertError(["project.json": manifest()], .missingScreenFile(file: "screens/home.json"))
    }

    func testScreenIDMismatch() {
        assertError(
            ["project.json": manifest(), "screens/home.json": screen(id: otherID)],
            .screenIDMismatch(file: "screens/home.json", expected: ScreenID(screenID), found: ScreenID(otherID))
        )
    }

    func testUnknownLinkTarget() {
        let regions = "[\(region("r", links: "[{ \"screen\": \"\(otherID)\", \"screenName\": \"Gone\" }]"))]"
        assertError(
            ["project.json": manifest(), "screens/home.json": screen(regions: regions)],
            .unknownLinkTarget(file: "screens/home.json", region: RegionID("r"), target: ScreenID(otherID))
        )
    }

    func testUnknownVariantScreen() {
        let groups = ", \"variantGroups\": [{ \"name\": \"G\", \"screens\": [\"\(screenID)\", \"\(otherID)\"] }]"
        assertError(
            ["project.json": manifest(extra: groups), "screens/home.json": screen()],
            .unknownVariantScreen(file: "project.json", group: "G", screen: ScreenID(otherID))
        )
    }

    func testDuplicateRegionID() {
        let regions = "[\(region("dup", children: "[\(region("dup"))]"))]"
        assertError(
            ["project.json": manifest(), "screens/home.json": screen(regions: regions)],
            .duplicateID(file: "screens/home.json", id: "dup")
        )
    }

    func testDuplicateRegionIDAcrossScreens() {
        let entries = """
            [{ "id": "\(screenID)", "name": "A", "file": "screens/a.json" },
             { "id": "\(otherID)", "name": "B", "file": "screens/b.json" }]
            """
        assertError(
            [
                "project.json": manifest(screens: entries),
                "screens/a.json": screen(regions: "[\(region("same"))]"),
                "screens/b.json": screen(id: otherID, regions: "[\(region("same"))]"),
            ],
            .duplicateID(file: "screens/b.json", id: "same")
        )
    }

    func testDuplicateScreenID() {
        let entries = """
            [{ "id": "\(screenID)", "name": "A", "file": "screens/a.json" },
             { "id": "\(screenID)", "name": "B", "file": "screens/b.json" }]
            """
        assertError(
            ["project.json": manifest(screens: entries), "screens/a.json": screen(), "screens/b.json": screen()],
            .duplicateID(file: "project.json", id: screenID)
        )
    }

    func testUnknownScreenKind() {
        assertError(
            ["project.json": manifest(), "screens/home.json": screen(kind: "drawer")],
            .unknownKind(file: "screens/home.json", kind: "drawer")
        )
    }

    func testUnknownRegionKind() {
        assertError(
            ["project.json": manifest(), "screens/home.json": screen(regions: "[\(region("r", kind: "slider"))]")],
            .unknownKind(file: "screens/home.json", kind: "slider")
        )
    }

    func testExplicitOpenKindReadsAsOpen() throws {
        let project = try ProjectPackage.read([
            "project.json": manifest(), "screens/home.json": screen(regions: "[\(region("r", kind: "open"))]"),
        ])
        XCTAssertEqual(project.screens[0].regions[0].kind, .open)
    }

    func testDerivedFieldsAreIgnoredOnRead() throws {
        let entries =
            "[{ \"id\": \"\(screenID)\", \"name\": \"Stale manifest name\", \"file\": \"screens/home.json\" }]"
        let regions = "[\(region("r", links: "[{ \"screen\": \"\(screenID)\", \"screenName\": \"Stale\" }]"))]"
        let project = try ProjectPackage.read([
            "project.json": manifest(screens: entries), "screens/home.json": screen(regions: regions),
        ])
        XCTAssertEqual(project.screens[0].name, "Home")
        let written = ProjectPackage.write(project: project).tree
        XCTAssertFalse(Fixtures.string(written["project.json"]).contains("Stale"))
        XCTAssertTrue(Fixtures.string(written["screens/home.json"]).contains("\"screenName\": \"Home\""))
    }

    func testUnreadableEditorStateGivesDefaults() throws {
        let project = try ProjectPackage.read([
            "project.json": manifest(), "screens/home.json": screen(), ".editor-state.json": Data("garbage".utf8),
        ])
        XCTAssertEqual(project.editorState, EditorState())
    }
}
