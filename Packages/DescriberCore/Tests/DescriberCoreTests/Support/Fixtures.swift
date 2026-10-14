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
    /// The example project's Markdown and single-file JSON exports, written by `testRegenerateExample`.
    static let exampleMarkdown = repositoryRoot.appendingPathComponent("Schema/examples/acme.md")
    static let exampleJSON = repositoryRoot.appendingPathComponent("Schema/examples/acme.json")

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

extension Fixtures {
    /// Everything the project would write, for comparing before and after an edit.
    static func bytes(_ project: Project) -> PackageTree {
        ProjectPackage.write(project: project).tree
    }

    /// A screen with an outer region containing an inner one, and a separate sibling:
    ///
    ///     outer  (0, 0, 200 × 200)
    ///       inner  (20, 20, 100 × 100)
    ///     side   (300, 0, 100 × 100)
    static func nestedProject() -> (project: Project, screen: Screen, outer: Region, inner: Region, side: Region) {
        let inner = Region(id: RegionID("inner"), title: "Inner", frame: Frame(x: 20, y: 20, w: 100, h: 100))
        let outer = Region(
            id: RegionID("outer"),
            title: "Outer",
            frame: Frame(x: 0, y: 0, w: 200, h: 200),
            children: [inner]
        )
        let side = Region(id: RegionID("side"), title: "Side", frame: Frame(x: 300, y: 0, w: 100, h: 100))
        let screen = Screen(
            id: ScreenID("00000000-0000-4000-8000-000000000001"),
            name: "Home",
            viewport: Viewport(width: 400, height: 800),
            regions: [outer, side]
        )
        return (Project(name: "Test", screens: [screen]), screen, outer, inner, side)
    }

    /// Titles of the screen's regions as an outline, such as `["Outer", "  Inner", "Side"]`.
    static func outline(_ screen: Screen) -> [String] {
        func walk(_ regions: [Region], depth: Int) -> [String] {
            regions.flatMap { [String(repeating: "  ", count: depth) + $0.title] + walk($0.children, depth: depth + 1) }
        }
        return walk(screen.regions, depth: 0)
    }
}
