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

    // MARK: Encoding cache

    func testACachedWriteReusesTheTextOfUnchangedFiles() throws {
        let project = AcmeExample.make()
        let cache = PackageEncodingCache()
        let first = ProjectPackage.write(project: project, cache: cache)
        try XCTUnwrap(project.screen(withID: AcmeExample.accountMenu)).regions[0].title = "Account"
        let second = ProjectPackage.write(project: project, previous: first.tree, cache: cache)
        XCTAssertEqual(second, ProjectPackage.write(project: project, previous: first.tree))
        XCTAssertEqual(second.changed, ["screens/account-menu.json"])
    }

    /// A title replaced by a canonically equivalent one with different bytes is `==` but must still be rewritten.
    func testACachedWriteRewritesCanonicallyEquivalentText() throws {
        let project = AcmeExample.make()
        let region = try XCTUnwrap(project.screen(withID: AcmeExample.accountMenu)).regions[0]
        region.title = "Caf\u{E9}"
        let cache = PackageEncodingCache()
        let first = ProjectPackage.write(project: project, cache: cache)
        region.title = "Cafe\u{301}"
        let second = ProjectPackage.write(project: project, previous: first.tree, cache: cache)
        XCTAssertEqual(second, ProjectPackage.write(project: project, previous: first.tree))
        XCTAssertEqual(second.changed, ["screens/account-menu.json"])
    }

    /// Random edits to a multi-screen project, written after each with one long-lived cache and without one: the
    /// results are the same every time. Renames change link names in other screens' files and can collide, and
    /// reorders can change which screen gets a numbered slug. A failure names its seed and step.
    func testCachedWritesMatchUncachedWritesAfterRandomEdits() throws {
        for seed in UInt64(0)..<40 {
            var random = SeededGenerator(seed: seed)
            let project = Project.stressTest(regionCount: 24, screenCount: 4)
            let session = EditSession(project: project)
            let cache = PackageEncodingCache()
            var tree = ProjectPackage.write(project: project, cache: cache).tree
            for step in 0..<30 {
                try applyRandomEdit(to: session, using: &random)
                let cached = ProjectPackage.write(project: project, previous: tree, cache: cache)
                let uncached = ProjectPackage.write(project: project, previous: tree)
                XCTAssertEqual(cached, uncached, "seed \(seed), step \(step)")
                tree = ProjectPackage.applying(cached.changes, to: tree)
            }
        }
    }

    private func applyRandomEdit(to session: EditSession, using random: inout SeededGenerator) throws {
        let project = session.project
        guard let screen = project.screens.randomElement(using: &random) else { return }
        let regions = screen.allRegions
        let names = ["Home", "home", "Settings", "Caf\u{E9}", "Cafe\u{301}", "Stress 1", "Stress 2"]
        switch random.int(0...9) {
        case 0, 1:
            guard let region = regions.randomElement(using: &random) else { return }
            try session.perform(RegionCommands.setTitle(names.randomElement(using: &random)!, of: region.id))
        case 2:
            guard let region = regions.randomElement(using: &random) else { return }
            try session.perform(RegionCommands.setDescription("Note \(random.int(0...3))", of: region.id))
        case 3:
            guard let region = regions.randomElement(using: &random) else { return }
            try session.perform(
                MoveRegions(screen: screen.id, regions: [region.id], dx: random.int(-40...40), dy: random.int(-40...40))
            )
        case 4, 5:
            try session.perform(ScreenCommands.rename(screen.id, to: names.randomElement(using: &random)!))
        case 6:
            try session.perform(ReorderScreen(screen.id, to: random.int(0...(project.screens.count - 1))))
        case 7:
            if project.screens.count > 2, random.chance(0.5) {
                try session.perform(DeleteScreen(screen.id))
            } else {
                try session.perform(DuplicateScreen(screen.id))
            }
        case 8:
            project.editorState.lastActiveScreen = random.chance(0.5) ? screen.id : nil
        default:
            if session.canUndo {
                try session.undo()
            }
        }
    }
}
