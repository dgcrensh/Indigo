import XCTest

@testable import DescriberCore

final class ProjectPackageTests: XCTestCase {
    func testSlugs() {
        XCTAssertEqual(Slug.make("Login"), "login")
        XCTAssertEqual(Slug.make("Login (Desktop)"), "login-desktop")
        XCTAssertEqual(Slug.make("  Reset   Password!! "), "reset-password")
        XCTAssertEqual(Slug.make("Café Menü"), "cafe-menu")
        XCTAssertEqual(Slug.make("Step 2 of 3"), "step-2-of-3")
        XCTAssertEqual(Slug.make("???"), "screen")
        XCTAssertEqual(Slug.make(""), "screen")
    }

    func testCollisionsGetNumberedSuffixesInSidebarOrder() {
        XCTAssertEqual(Slug.unique(["Login", "Login", "login!", "Other"]), ["login", "login-2", "login-3", "other"])
    }

    func testTwoScreensNamedLoginGetSeparateFiles() {
        let project = Project(
            name: "P",
            screens: [
                Screen(name: "Login", viewport: Viewport(width: 10, height: 10)),
                Screen(name: "Login", viewport: Viewport(width: 20, height: 20)),
            ]
        )
        let tree = ProjectPackage.write(project: project).tree
        XCTAssertEqual(Set(tree.keys), ["project.json", "screens/login.json", "screens/login-2.json"])
    }

    func testRenameMovesTheScreenFile() throws {
        let project = AcmeExample.make()
        let first = ProjectPackage.write(project: project)
        try XCTUnwrap(project.screen(withID: AcmeExample.settings)).name = "Preferences"

        let second = ProjectPackage.write(project: project, previous: first.tree)
        XCTAssertNotNil(second.tree["screens/preferences.json"])
        XCTAssertNil(second.tree["screens/settings.json"])
        XCTAssertEqual(second.removed, ["screens/settings.json"])
        XCTAssertTrue(second.changed.contains("screens/preferences.json"))
    }

    func testDeleteRemovesTheScreenFile() {
        let project = AcmeExample.make()
        let first = ProjectPackage.write(project: project)
        project.screens.removeAll { $0.id == AcmeExample.loginDesktop }
        project.variantGroups = []

        let second = ProjectPackage.write(project: project, previous: first.tree)
        XCTAssertEqual(second.removed, ["screens/login-desktop.json"])
    }

    func testUnchangedFilesAreReported() throws {
        let project = AcmeExample.make()
        let first = ProjectPackage.write(project: project)
        XCTAssertEqual(ProjectPackage.write(project: project, previous: first.tree).unchanged, Set(first.tree.keys))

        try XCTUnwrap(project.screen(withID: AcmeExample.accountMenu)).regions[0].title = "Account"
        let second = ProjectPackage.write(project: project, previous: first.tree)
        XCTAssertEqual(second.changed, ["screens/account-menu.json"])
        XCTAssertEqual(second.removed, [])
    }

    func testUnknownFilesAreLeftAlone() throws {
        let project = AcmeExample.make()
        var previous = ProjectPackage.write(project: project).tree
        previous["references/sketch.png"] = Data([1, 2, 3])
        previous["screens/notes.json"] = Data("{}".utf8)
        previous["README.md"] = Data("hi".utf8)

        let reread = try ProjectPackage.read(previous)
        let result = ProjectPackage.write(project: reread, previous: previous)
        XCTAssertEqual(result.removed, [])
        XCTAssertNil(result.tree["references/sketch.png"])
        XCTAssertNil(result.tree["screens/notes.json"])
        XCTAssertEqual(result.unchanged, Set(result.tree.keys))
    }

    func testDefaultEditorStateIsNotWrittenAndAStaleOneIsRemoved() {
        let (project, screen) = Fixtures.simpleProject()
        XCTAssertNil(ProjectPackage.write(project: project).tree[".editor-state.json"])

        project.editorState.lastActiveScreen = screen.id
        let withState = ProjectPackage.write(project: project)
        XCTAssertNotNil(withState.tree[".editor-state.json"])

        project.editorState = EditorState()
        XCTAssertEqual(ProjectPackage.write(project: project, previous: withState.tree).removed, [".editor-state.json"])
    }

    func testWritingTheExampleOverItselfChangesNothing() throws {
        let tree = try Fixtures.readTree(at: Fixtures.examplePackage)
        let result = ProjectPackage.write(project: try ProjectPackage.read(tree), previous: tree)
        XCTAssertTrue(result.changes.isEmpty)
        XCTAssertEqual(ProjectPackage.applying(result.changes, to: tree), tree)
    }

    func testRenameChangesWriteTheManifestAndNewFileAndDeleteTheOldOne() throws {
        let project = AcmeExample.make()
        let first = ProjectPackage.write(project: project)
        // Nothing links to Login (Desktop), so no other screen file carries its name.
        try XCTUnwrap(project.screen(withID: AcmeExample.loginDesktop)).name = "Login (Wide)"

        let changes = ProjectPackage.write(project: project, previous: first.tree).changes
        XCTAssertEqual(Set(changes.written.keys), ["project.json", "screens/login-wide.json"])
        XCTAssertEqual(changes.deleted, ["screens/login-desktop.json"])
    }

    func testApplyingChangesKeepsFilesTheProjectDoesNotOwn() throws {
        let project = AcmeExample.make()
        var previous = ProjectPackage.write(project: project).tree
        let unknown: PackageTree = [
            ".gitignore": Data(".editor-state.json\n".utf8),
            "references/login.png": Data([0x89, 0x50, 0x4E, 0x47]),
        ]
        previous.merge(unknown) { old, _ in old }
        try XCTUnwrap(project.screen(withID: AcmeExample.settings)).name = "Preferences"
        project.screens.removeAll { $0.id == AcmeExample.accountMenu }

        let result = ProjectPackage.write(project: project, previous: previous)
        let applied = ProjectPackage.applying(result.changes, to: previous)
        XCTAssertEqual(applied, result.tree.merging(unknown) { old, _ in old })
        XCTAssertNil(applied["screens/settings.json"])
        XCTAssertNil(applied["screens/account-menu.json"])
    }
}
