import DescriberCore
import Foundation

enum Fixtures {
    /// The repository root, found from this file's location.
    static let repositoryRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // Support
        .deletingLastPathComponent()  // DescriberCoreTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // DescriberCore
        .deletingLastPathComponent()  // Packages
        .deletingLastPathComponent()

    static let examplePackage = repositoryRoot.appendingPathComponent("Schema/examples/acme.uidesc")
    static let schema = repositoryRoot.appendingPathComponent("Schema/uidesc-1.schema.json")

    /// Every file under `directory`, keyed by relative path.
    static func readTree(at directory: URL) throws -> PackageTree {
        var tree: PackageTree = [:]
        let base = directory.standardizedFileURL.path
        guard let enumerator = FileManager.default.enumerator(atPath: base) else { return tree }
        while let relative = enumerator.nextObject() as? String {
            let url = URL(fileURLWithPath: base).appendingPathComponent(relative)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue {
                tree[relative] = try Data(contentsOf: url)
            }
        }
        return tree
    }

    /// Replaces `directory` with exactly the files in `tree`.
    static func writeTree(_ tree: PackageTree, to directory: URL) throws {
        try? FileManager.default.removeItem(at: directory)
        for (path, data) in tree {
            let url = directory.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url)
        }
    }

    static func string(_ data: Data?) -> String {
        data.map { String(decoding: $0, as: UTF8.self) } ?? "<missing>"
    }

    /// A one-screen project for focused tests.
    static func simpleProject() -> (Project, Screen) {
        let screen = Screen(
            id: ScreenID("00000000-0000-4000-8000-000000000001"),
            name: "Home",
            viewport: Viewport(preset: "iphone-15", width: 393, height: 852)
        )
        return (Project(name: "Test", screens: [screen]), screen)
    }
}
