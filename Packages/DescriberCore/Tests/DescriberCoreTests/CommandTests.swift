import XCTest

@testable import DescriberCore

final class CommandTests: XCTestCase {
    /// Performs `command`, then checks that undo restores the exact bytes and redo reproduces the applied bytes.
    @discardableResult
    private func assertUndoable(
        _ command: Command,
        on project: Project,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> EditSession {
        let session = EditSession(project: project)
        let before = Fixtures.bytes(project)
        try session.perform(command)
        let applied = Fixtures.bytes(project)
        XCTAssertNotEqual(applied, before, "\(command.actionName) changed nothing", file: file, line: line)
        XCTAssertEqual(session.undoActionName, command.actionName, file: file, line: line)

        try session.undo()
        XCTAssertEqual(Fixtures.bytes(project), before, "Undo of \(command.actionName)", file: file, line: line)
        XCTAssertEqual(session.redoActionName, command.actionName, file: file, line: line)

        try session.redo()
        XCTAssertEqual(Fixtures.bytes(project), applied, "Redo of \(command.actionName)", file: file, line: line)
        return session
    }

    // MARK: Edit session

    func testEveryRegionCommandUndoesAndRedoesToTheSameBytes() throws {
        let screen = AcmeExample.settings
        let list = RegionID("9be4bcfc-49b6-4a08-b2e6-cc3ababced20")
        let about = RegionID("6bf46c69-7d2c-4f82-aeea-cbe226e87555")
        let notifications = RegionID("830e07bc-1e39-4f10-92bd-4acefaecbd38")
        let commands: [Command] = [
            CreateRegion(screen: screen, frame: Frame(x: 20, y: 300, w: 100, h: 40), title: "New"),
            MoveRegions(screen: screen, regions: [list], dx: 10, dy: 20),
            MoveRegions(screen: screen, regions: [notifications, about], dx: 0, dy: -8),
            ResizeRegion(screen: screen, region: list, frame: Frame(x: 0, y: 100, w: 393, h: 400)),
            DeleteRegions(screen: screen, regions: [list]),
            ReorderRegion(screen: screen, region: notifications, to: .front),
            ReorderRegion(screen: screen, region: about, to: .back),
            PasteRegions(screen: AcmeExample.login, regions: [AcmeExample.make().region(withID: list)!.region]),
            RegionCommands.setTitle("Renamed", of: list),
            RegionCommands.setDescription("New text", of: list),
            RegionCommands.setKind(.container, of: list),
            RegionCommands.setLinks([Link(screen: AcmeExample.login, trigger: "swipe")], of: list),
            RegionCommands.setScroll(nil, of: list),
        ]
        for command in commands {
            try assertUndoable(command, on: AcmeExample.make())
        }
    }

    func testEveryScreenCommandUndoesAndRedoesToTheSameBytes() throws {
        let commands: [Command] = [
            AddScreen(name: "Onboarding", viewport: Viewport(width: 393, height: 852), at: 1),
            DuplicateScreen(AcmeExample.settings),
            ReorderScreen(AcmeExample.accountMenu, to: 0),
            DeleteScreen(AcmeExample.settings),
            NewVariant(of: AcmeExample.settings, viewport: Viewport(preset: "ipad", width: 820, height: 1180)),
            NewVariant(of: AcmeExample.login, viewport: Viewport(preset: "ipad", width: 820, height: 1180)),
            GroupVariants([AcmeExample.resetPassword, AcmeExample.login], name: "Auth"),
            UngroupVariants(containing: AcmeExample.login),
            ScreenCommands.rename(AcmeExample.resetPassword, to: "Recover"),
            ScreenCommands.setKind(.sheet, of: AcmeExample.resetPassword),
            ScreenCommands.setViewport(Viewport(width: 100, height: 100), of: AcmeExample.resetPassword),
            ScreenCommands.setScroll(Scroll(axis: .both, contentWidth: 1, contentHeight: 1), of: AcmeExample.login),
        ]
        for command in commands {
            try assertUndoable(command, on: AcmeExample.make())
        }
    }

    func testPerformingANewCommandClearsRedo() throws {
        let (project, screen, outer, _, _) = Fixtures.nestedProject()
        let session = EditSession(project: project)
        try session.perform(MoveRegions(screen: screen.id, regions: [outer.id], dx: 1, dy: 1))
        try session.undo()
        XCTAssertTrue(session.canRedo)
        try session.perform(RegionCommands.setTitle("Other", of: outer.id))
        XCTAssertFalse(session.canRedo)
    }

    func testCompositeOfThreeMovesIsOneUndoStep() throws {
        let (project, screen, outer, _, side) = Fixtures.nestedProject()
        let before = Fixtures.bytes(project)
        let session = EditSession(project: project)
        try session.perform(
            CompositeCommand(
                actionName: "Move Regions",
                commands: [
                    MoveRegions(screen: screen.id, regions: [outer.id], dx: 4, dy: 0),
                    MoveRegions(screen: screen.id, regions: [side.id], dx: 0, dy: 4),
                    MoveRegions(screen: screen.id, regions: [outer.id, side.id], dx: 4, dy: 4),
                ]
            )
        )
        XCTAssertEqual(session.undoDepth, 1)
        XCTAssertEqual(outer.frame.x, 8)
        try session.undo()
        XCTAssertEqual(Fixtures.bytes(project), before)
        XCTAssertFalse(session.canUndo)
    }

    func testFailingCompositeLeavesTheProjectUnchanged() {
        let (project, screen, outer, _, _) = Fixtures.nestedProject()
        let before = Fixtures.bytes(project)
        let session = EditSession(project: project)
        let composite = CompositeCommand(
            actionName: "Move",
            commands: [
                MoveRegions(screen: screen.id, regions: [outer.id], dx: 4, dy: 0),
                ResizeRegion(screen: screen.id, region: outer.id, frame: Frame(x: 0, y: 0, w: 3, h: 3)),
            ]
        )
        XCTAssertThrowsError(try session.perform(composite))
        XCTAssertEqual(Fixtures.bytes(project), before)
        XCTAssertFalse(session.canUndo)
    }

    func testUndoKeepsRegionIdentity() throws {
        let (project, screen, outer, inner, _) = Fixtures.nestedProject()
        let session = EditSession(project: project)
        try session.perform(DeleteRegions(screen: screen.id, regions: [outer.id]))
        try session.undo()
        XCTAssertTrue(screen.regions[0] === outer)
        XCTAssertTrue(outer.children[0] === inner)
    }

    // MARK: Region commands

    func testCreateOrResizeBelowMinimumSizeIsRejectedAndChangesNothing() {
        let (project, screen, outer, _, _) = Fixtures.nestedProject()
        let before = Fixtures.bytes(project)
        let session = EditSession(project: project)
        let small = Frame(x: 10, y: 10, w: 3, h: 10)
        XCTAssertThrowsError(try session.perform(CreateRegion(screen: screen.id, frame: small))) { error in
            XCTAssertEqual(error as? EditError, .belowMinimumSize(small))
        }
        XCTAssertThrowsError(try session.perform(ResizeRegion(screen: screen.id, region: outer.id, frame: small)))
        XCTAssertEqual(Fixtures.bytes(project), before)
        XCTAssertFalse(session.canUndo)

        XCTAssertNoThrow(try session.perform(CreateRegion(screen: screen.id, frame: Frame(x: 0, y: 0, w: 4, h: 4))))
    }

    func testCreateSnapsWhenGivenAGrid() throws {
        let (project, screen, _, _, _) = Fixtures.nestedProject()
        let id = RegionID("snapped")
        _ = try CreateRegion(screen: screen.id, frame: Frame(x: 3, y: 405, w: 30, h: 30), id: id, grid: 8)
            .apply(to: project)
        XCTAssertEqual(project.region(withID: id)?.region.frame, Frame(x: 0, y: 408, w: 32, h: 24))
    }

    func testMovingAParentMovesEveryDescendantByTheSameDelta() throws {
        let (project, screen, outer, inner, _) = Fixtures.nestedProject()
        let grandchild = Region(id: RegionID("grand"), title: "Grand", frame: Frame(x: 30, y: 30, w: 10, h: 10))
        inner.children = [grandchild]
        let frames = [outer, inner, grandchild].map(\.frame)

        _ = try MoveRegions(screen: screen.id, regions: [outer.id], dx: 10, dy: 20).apply(to: project)
        XCTAssertEqual([outer, inner, grandchild].map(\.frame), frames.map { $0.offsetBy(dx: 10, dy: 20) })
        XCTAssertEqual(Fixtures.outline(screen), ["Outer", "  Inner", "    Grand", "Side"])
    }

    func testMovingARegionAndItsChildTogetherMovesTheChildOnce() throws {
        let (project, screen, outer, inner, _) = Fixtures.nestedProject()
        _ = try MoveRegions(screen: screen.id, regions: [inner.id, outer.id], dx: 5, dy: 5).apply(to: project)
        XCTAssertEqual(inner.frame, Frame(x: 25, y: 25, w: 100, h: 100))
    }

    func testMoveWithGridLandsTheFirstRegionOnTheGrid() throws {
        let (project, screen, outer, inner, _) = Fixtures.nestedProject()
        _ = try MoveRegions(screen: screen.id, regions: [outer.id], dx: 13, dy: 2, grid: 8).apply(to: project)
        XCTAssertEqual(outer.frame, Frame(x: 16, y: 0, w: 200, h: 200))
        XCTAssertEqual(inner.frame, Frame(x: 36, y: 20, w: 100, h: 100))
    }

    func testResizingAParentSoAChildNoLongerFitsReparentsItAndUndoPutsItBack() throws {
        let (project, screen, outer, inner, _) = Fixtures.nestedProject()
        let before = Fixtures.outline(screen)
        let session = EditSession(project: project)
        try session.perform(
            ResizeRegion(screen: screen.id, region: outer.id, frame: Frame(x: 0, y: 0, w: 100, h: 200), edges: [.right])
        )
        XCTAssertEqual(inner.frame, Frame(x: 20, y: 20, w: 100, h: 100), "Resizing never moves children")
        XCTAssertNil(RegionIndex(screen: screen).parent(of: inner.id))
        XCTAssertEqual(Fixtures.outline(screen), ["Outer", "Side", "Inner"])

        try session.undo()
        XCTAssertEqual(Fixtures.outline(screen), before)
        XCTAssertEqual(RegionIndex(screen: screen).parent(of: inner.id)?.id, outer.id)
    }

    func testResizedRegionIsReparentedToo() throws {
        let (project, screen, outer, inner, _) = Fixtures.nestedProject()
        _ = try ResizeRegion(screen: screen.id, region: inner.id, frame: Frame(x: 20, y: 20, w: 300, h: 100))
            .apply(to: project)
        XCTAssertNil(RegionIndex(screen: screen).parent(of: inner.id))
        XCTAssertTrue(outer.children.isEmpty)
    }

    func testDeleteRemovesDescendants() throws {
        let (project, screen, outer, inner, _) = Fixtures.nestedProject()
        _ = try DeleteRegions(screen: screen.id, regions: [outer.id, inner.id]).apply(to: project)
        XCTAssertEqual(Fixtures.outline(screen), ["Side"])
        XCTAssertNil(project.region(withID: inner.id))
    }

    func testBringToFrontAndSendToBack() throws {
        let (project, screen, outer, _, side) = Fixtures.nestedProject()
        _ = try ReorderRegion(screen: screen.id, region: outer.id, to: .front).apply(to: project)
        XCTAssertEqual(screen.regions.map(\.id), [side.id, outer.id])
        _ = try ReorderRegion(screen: screen.id, region: outer.id, to: .back).apply(to: project)
        XCTAssertEqual(screen.regions.map(\.id), [outer.id, side.id])
    }

    func testPastedRegionsHaveNewIDsThroughoutAndKeepTheirLinks() throws {
        let source = AcmeExample.make()
        let form = try XCTUnwrap(source.region(withID: RegionID("90c192cf-d3ac-44af-8f21-ddb66cad4a26"))?.region)
        let project = AcmeExample.make()
        let paste = PasteRegions(screen: AcmeExample.resetPassword, regions: [form])
        let session = EditSession(project: project)
        try session.perform(paste)

        let pasted = try XCTUnwrap(paste.pasted.first)
        let originalIDs = Set(form.subtree.map(\.id))
        XCTAssertTrue(Set(pasted.subtree.map(\.id)).isDisjoint(with: originalIDs))
        XCTAssertEqual(pasted.subtree.count, form.subtree.count)
        XCTAssertEqual(pasted.subtree.map(\.links), form.subtree.map(\.links))
        XCTAssertEqual(project.region(withID: pasted.id)?.screen.id, AcmeExample.resetPassword)
        XCTAssertNoThrow(try ProjectPackage.read(Fixtures.bytes(project)), "IDs are still unique project-wide")
    }

    func testPasteIntoAnExplicitParent() throws {
        let (project, screen, _, inner, side) = Fixtures.nestedProject()
        let paste = PasteRegions(screen: screen.id, regions: [side], parent: inner.id)
        _ = try paste.apply(to: project)
        XCTAssertEqual(inner.children.map(\.id), paste.pasted.map(\.id))
    }

    // MARK: Screen commands

    func testDuplicatedScreensHaveNewIDsAndKeepLinks() throws {
        let project = AcmeExample.make()
        let duplicate = DuplicateScreen(AcmeExample.login)
        _ = try duplicate.apply(to: project)

        let original = try XCTUnwrap(project.screen(withID: AcmeExample.login))
        let copy = try XCTUnwrap(project.screen(withID: duplicate.newID))
        XCTAssertEqual(project.screens.map(\.name).prefix(2), ["Login", "Login Copy"])
        XCTAssertTrue(Set(copy.allRegions.map(\.id)).isDisjoint(with: original.allRegions.map(\.id)))
        XCTAssertEqual(copy.allRegions.map(\.links), original.allRegions.map(\.links))
        XCTAssertEqual(copy.allRegions.map(\.frame), original.allRegions.map(\.frame))
        XCTAssertNoThrow(try ProjectPackage.read(Fixtures.bytes(project)))
    }

    func testDeletingAScreenRemovesEveryLinkToItAndUndoRestoresThem() throws {
        let project = AcmeExample.make()
        let incoming = ScreenCommands.incomingLinks(to: AcmeExample.settings, in: project)
        XCTAssertEqual(
            Set(incoming.map(\.screen)), [AcmeExample.login, AcmeExample.loginDesktop, AcmeExample.accountMenu])

        let before = Fixtures.bytes(project)
        let session = EditSession(project: project)
        try session.perform(DeleteScreen(AcmeExample.settings))
        XCTAssertNil(project.screen(withID: AcmeExample.settings))
        let remaining = project.screens.flatMap(\.allRegions).flatMap(\.links)
        XCTAssertFalse(remaining.contains { $0.screen == AcmeExample.settings })
        XCTAssertNoThrow(try ProjectPackage.read(Fixtures.bytes(project)), "No dangling links are written")

        try session.undo()
        XCTAssertEqual(Fixtures.bytes(project), before)
    }

    func testDeletingAScreenDropsItFromItsVariantGroup() throws {
        let project = AcmeExample.make()
        _ = try DeleteScreen(AcmeExample.loginDesktop).apply(to: project)
        XCTAssertEqual(project.variantGroups, [VariantGroup(name: "Login", screens: [AcmeExample.login])])
        _ = try DeleteScreen(AcmeExample.login).apply(to: project)
        XCTAssertEqual(project.variantGroups, [])
    }

    func testSetViewportLeavesRegionsAlone() throws {
        let project = AcmeExample.make()
        let screen = try XCTUnwrap(project.screen(withID: AcmeExample.login))
        let frames = screen.allRegions.map(\.frame)
        _ = try ScreenCommands.setViewport(Viewport(width: 200, height: 200), of: screen.id).apply(to: project)
        XCTAssertEqual(screen.allRegions.map(\.frame), frames)
    }

    func testNewVariantJoinsOrCreatesTheGroup() throws {
        let project = AcmeExample.make()
        let ipad = Viewport(preset: "ipad", width: 820, height: 1180)
        let joined = NewVariant(of: AcmeExample.login, viewport: ipad)
        _ = try joined.apply(to: project)
        XCTAssertEqual(project.variantGroups[0].screens, [AcmeExample.login, AcmeExample.loginDesktop, joined.newID])
        XCTAssertEqual(project.screen(withID: joined.newID)?.name, "Login (ipad)")
        XCTAssertEqual(project.screen(withID: joined.newID)?.viewport, ipad)
        XCTAssertEqual(project.screens.map(\.id).firstIndex(of: joined.newID), 2, "After the group's last screen")

        let created = NewVariant(of: AcmeExample.settings, viewport: ipad, name: "Settings (iPad)")
        _ = try created.apply(to: project)
        XCTAssertEqual(
            project.variantGroups[1], VariantGroup(name: "Settings", screens: [AcmeExample.settings, created.newID]))
        XCTAssertEqual(project.screens.map(\.id).firstIndex(of: created.newID), 5, "Right after the original")
    }

    func testGroupMovesScreensOutOfTheirOldGroup() throws {
        let project = AcmeExample.make()
        _ = try GroupVariants([AcmeExample.loginDesktop, AcmeExample.resetPassword], name: "Mixed").apply(to: project)
        XCTAssertEqual(
            project.variantGroups,
            [
                VariantGroup(name: "Login", screens: [AcmeExample.login]),
                VariantGroup(name: "Mixed", screens: [AcmeExample.loginDesktop, AcmeExample.resetPassword]),
            ]
        )
        XCTAssertThrowsError(try GroupVariants([AcmeExample.login], name: "Alone").apply(to: project))
    }

    func testCommandsOnMissingTargetsThrow() {
        let project = AcmeExample.make()
        let missingScreen = ScreenID("ffffffff-0000-4000-8000-000000000000")
        let missingRegion = RegionID("nope")
        XCTAssertThrowsError(try RegionCommands.setTitle("x", of: missingRegion).apply(to: project)) {
            XCTAssertEqual($0 as? EditError, .regionNotFound(missingRegion))
        }
        XCTAssertThrowsError(try DeleteScreen(missingScreen).apply(to: project)) {
            XCTAssertEqual($0 as? EditError, .screenNotFound(missingScreen))
        }
        XCTAssertThrowsError(try ReorderScreen(AcmeExample.login, to: 9).apply(to: project)) {
            XCTAssertEqual($0 as? EditError, .indexOutOfRange(9))
        }
    }

    func testExampleProjectStillResavesAfterAnEditAndItsUndo() throws {
        let tree = try Fixtures.readTree(at: Fixtures.examplePackage)
        let project = try ProjectPackage.read(tree)
        let session = EditSession(project: project)
        try session.perform(DeleteScreen(AcmeExample.settings))
        try session.undo()
        XCTAssertEqual(ProjectPackage.write(project: project, previous: tree).unchanged, Set(tree.keys))
    }
}
