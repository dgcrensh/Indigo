import XCTest

@testable import DescriberCore

/// The example project must re-save byte for byte and match the schema. `scripts/check.sh` runs this class by
/// name so a failure names the example project.
final class ExampleProjectTests: XCTestCase {
    func testExampleProjectResavesByteForByte() throws {
        let tree = try Fixtures.readTree(at: Fixtures.examplePackage)
        XCTAssertFalse(tree.isEmpty, "No files found at \(Fixtures.examplePackage.path)")
        let project = try ProjectPackage.read(tree)
        let result = ProjectPackage.write(project: project, previous: tree)

        XCTAssertEqual(Set(result.tree.keys), Set(tree.keys), "The example's file list changed on re-save")
        XCTAssertEqual(result.removed, [])
        for (path, data) in result.tree where tree[path] != data {
            XCTFail("\(path) changed on re-save. Written:\n\(Fixtures.string(data))")
        }
    }

    func testExampleProjectMatchesTheSchema() throws {
        let validator = try SchemaValidator(schema: Data(contentsOf: Fixtures.schema))
        let tree = try Fixtures.readTree(at: Fixtures.examplePackage)
        let jsonFiles = tree.filter { $0.key.hasSuffix(".json") && $0.key != ".editor-state.json" }
        XCTAssertEqual(jsonFiles.count, 6)
        for (path, data) in jsonFiles {
            let errors = try validator.validate(data)
            XCTAssertTrue(errors.isEmpty, "\(path):\n" + errors.map(\.description).joined(separator: "\n"))
        }
    }

    func testSchemaRejectsCommonMistakes() throws {
        let validator = try SchemaValidator(schema: Data(contentsOf: Fixtures.schema))
        let tree = try Fixtures.readTree(at: Fixtures.examplePackage)
        let login = Fixtures.string(tree["screens/login.json"])

        let emptyChildren = login.replacingOccurrences(
            of: "\"title\": \"Logo\",", with: "\"title\": \"Logo\", \"children\": [],")
        XCTAssertFalse(try validator.validate(Data(emptyChildren.utf8)).isEmpty)
        let openKind = login.replacingOccurrences(of: "\"kind\": \"image\"", with: "\"kind\": \"open\"")
        XCTAssertFalse(try validator.validate(Data(openKind.utf8)).isEmpty)
        let extraKey = login.replacingOccurrences(
            of: "\"title\": \"Logo\",", with: "\"title\": \"Logo\", \"color\": \"red\",")
        XCTAssertFalse(try validator.validate(Data(extraKey.utf8)).isEmpty)
    }

    func testExampleIsWhatTheGeneratorWrites() throws {
        let tree = try Fixtures.readTree(at: Fixtures.examplePackage)
        let generated = ProjectPackage.write(project: AcmeExample.make()).tree
        XCTAssertEqual(
            generated,
            tree,
            "Schema/examples/acme.uidesc is out of date. Run REGENERATE_EXAMPLE=1 swift test --filter testRegenerateExample"
        )
    }

    func testExampleExportsAreWhatTheExportersWrite() throws {
        let project = AcmeExample.make()
        let regenerate = "Run REGENERATE_EXAMPLE=1 swift test --filter testRegenerateExample"
        XCTAssertEqual(
            Fixtures.string(try Data(contentsOf: Fixtures.exampleMarkdown)),
            MarkdownExport.markdown(for: project),
            "Schema/examples/acme.md is out of date. \(regenerate)")
        XCTAssertEqual(
            Fixtures.string(try Data(contentsOf: Fixtures.exampleJSON)),
            Fixtures.string(ProjectJSONExport.data(for: project)),
            "Schema/examples/acme.json is out of date. \(regenerate)")
    }

    func testExampleJSONExportMatchesTheSchema() throws {
        let validator = try SchemaValidator(schema: Data(contentsOf: Fixtures.schema))
        let errors = try validator.validate(Data(contentsOf: Fixtures.exampleJSON))
        XCTAssertTrue(errors.isEmpty, errors.map(\.description).joined(separator: "\n"))
    }

    /// Rewrites `Schema/examples/acme.uidesc` and its exports from `AcmeExample` when `REGENERATE_EXAMPLE=1` is set.
    func testRegenerateExample() throws {
        guard ProcessInfo.processInfo.environment["REGENERATE_EXAMPLE"] == "1" else {
            throw XCTSkip("Set REGENERATE_EXAMPLE=1 to rewrite the example project.")
        }
        let project = AcmeExample.make()
        try Fixtures.writeTree(ProjectPackage.write(project: project).tree, to: Fixtures.examplePackage)
        try MarkdownExport.data(for: project).write(to: Fixtures.exampleMarkdown)
        try ProjectJSONExport.data(for: project).write(to: Fixtures.exampleJSON)
    }
}
