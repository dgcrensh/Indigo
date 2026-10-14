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

    /// One of every region command, on the example project. The undo audit below checks this list and
    /// `screenCommands` cover every command type.
    private static var regionCommands: [Command] {
        let screen = AcmeExample.settings
        let list = RegionID("9be4bcfc-49b6-4a08-b2e6-cc3ababced20")
        let about = RegionID("6bf46c69-7d2c-4f82-aeea-cbe226e87555")
        let notifications = RegionID("830e07bc-1e39-4f10-92bd-4acefaecbd38")
        return [
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
            RegionCommands.setScroll(Scroll(axis: .vertical, contentWidth: 100, contentHeight: 900), of: about),
            ReorderRegions(screen: screen, regions: [notifications, about], to: .back),
            CompositeCommand(
                actionName: "Move and Rename",
                commands: [
                    MoveRegions(screen: screen, regions: [about], dx: 4, dy: 4),
                    RegionCommands.setTitle("About Acme", of: about),
                ]),
        ]
    }

    func testEveryRegionCommandUndoesAndRedoesToTheSameBytes() throws {
        for command in Self.regionCommands {
            try assertUndoable(command, on: AcmeExample.make())
        }
    }

    private static var screenCommands: [Command] {
        [
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
            ReorderScreens([
                AcmeExample.settings, AcmeExample.login, AcmeExample.loginDesktop, AcmeExample.resetPassword,
                AcmeExample.accountMenu,
            ]),
            JoinVariants(AcmeExample.accountMenu, joining: AcmeExample.login),
            JoinVariants(AcmeExample.accountMenu, joining: AcmeExample.resetPassword),
            LeaveVariantGroup(AcmeExample.loginDesktop),
            RenameVariantGroup(containing: AcmeExample.login, to: "Sign in"),
        ]
    }

    func testEveryScreenCommandUndoesAndRedoesToTheSameBytes() throws {
        for command in Self.screenCommands {
            try assertUndoable(command, on: AcmeExample.make())
        }
    }

    /// The undo audit (milestone 12): every type that conforms to `Command` in the core's sources is applied by the
    /// round-trip tests above, directly or as the inverse one of them returns. A new command fails here until it has
    /// a round trip.
    func testEveryCommandTypeHasAnUndoTest() throws {
        var tested: Set<String> = []
        func collect(_ command: Command) {
            tested.insert(Self.typeName(of: command))
            if let composite = command as? CompositeCommand {
                composite.commands.forEach(collect)
            }
        }
        for command in Self.regionCommands + Self.screenCommands {
            collect(command)
            collect(try command.apply(to: AcmeExample.make()))
        }
        let declared = try Self.declaredCommandTypes()
        XCTAssertGreaterThan(declared.count, 20, "the source scan found the commands")
        XCTAssertEqual(declared.subtracting(tested), [], "command types without an undo round trip")
    }

    /// A command's type name without generic parameters, such as `SetRegionValue`.
    private static func typeName(of command: Command) -> String {
        let name = String(describing: type(of: command))
        return name.firstIndex(of: "<").map { String(name[..<$0]) } ?? name
    }

    /// The names of the types the core's sources declare as conforming to `Command`.
    private static func declaredCommandTypes() throws -> Set<String> {
        let sources = Fixtures.repositoryRoot.appendingPathComponent("Packages/DescriberCore/Sources/DescriberCore")
        let pattern = try NSRegularExpression(
            pattern: #"\b(?:struct|class|enum)\s+(\w+)(?:<[^>]*>)?\s*:[^{]*\bCommand\b"#)
        var names: Set<String> = []
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
        while let file = files?.nextObject() as? URL {
            guard file.pathExtension == "swift" else { continue }
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let range = Range(match.range(at: 1), in: text) {
                    names.insert(String(text[range]))
                }
            }
        }
        return names
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

    /// Twenty random region commands on a random screen, then undo all of them and redo all of them: the bytes come
    /// back to the start and then to the end, with the same region objects throughout.
    func testRandomCommandsUndoAndRedoToTheSameBytes() throws {
        for seed in UInt64(0)..<100 {
            let subject = RandomScreen(seed: seed)
            let screen = subject.screen
            var random = SeededGenerator(seed: seed &+ 2_000_000)
            let session = EditSession(project: subject.project)
            let start = Fixtures.bytes(subject.project)
            let startRegions = screen.allRegions
            for _ in 0..<20 {
                guard let command = Self.randomRegionCommand(on: subject, using: &random) else { continue }
                try? session.perform(command)
            }
            let end = Fixtures.bytes(subject.project)
            let endRegions = screen.allRegions
            let steps = session.undoDepth
            XCTAssertGreaterThan(steps, 10, "seed \(seed)")

            for _ in 0..<steps {
                try session.undo()
            }
            XCTAssertEqual(Fixtures.bytes(subject.project), start, "undo all, seed \(seed)")
            XCTAssertTrue(zip(screen.allRegions, startRegions).allSatisfy(===), "undo identity, seed \(seed)")
            for _ in 0..<steps {
                try session.redo()
            }
            XCTAssertEqual(Fixtures.bytes(subject.project), end, "redo all, seed \(seed)")
            XCTAssertTrue(zip(screen.allRegions, endRegions).allSatisfy(===), "redo identity, seed \(seed)")
        }
    }

    private static func randomRegionCommand(on subject: RandomScreen, using random: inout SeededGenerator) -> Command? {
        let screen = subject.screen
        let all = screen.allRegions
        guard let region = all.randomElement(using: &random) else { return nil }
        let some = (0..<random.int(1...8)).map { _ in all.randomElement(using: &random)!.id }
        let offsets = subject.offsets
        switch random.int(0...8) {
        case 0:
            return CreateRegion(
                screen: screen.id, frame: RandomScreen.frame(in: region.frame, using: &random), scrollOffsets: offsets)
        case 1:
            return MoveRegions(
                screen: screen.id, regions: some, dx: random.int(-200...200), dy: random.int(-200...200),
                scrollOffsets: offsets)
        case 2:
            let frame = region.frame
            return ResizeRegion(
                screen: screen.id, region: region.id,
                frame: Frame(x: frame.x, y: frame.y, w: random.int(4...frame.w + 40), h: random.int(4...frame.h + 40)),
                scrollOffsets: offsets)
        case 3:
            return DeleteRegions(screen: screen.id, regions: some)
        case 4:
            return ReorderRegion(screen: screen.id, region: region.id, to: random.chance(0.5) ? .front : .back)
        case 5:
            return ReorderRegions(screen: screen.id, regions: some, to: random.chance(0.5) ? .front : .back)
        case 6:
            return PasteRegions(
                screen: screen.id, regions: some.compactMap { id in all.first { $0.id == id } },
                parent: random.chance(0.3) ? region.id : nil, scrollOffsets: offsets)
        case 7:
            let scroll = random.chance(0.5) ? nil : Scroll(axis: .vertical, contentWidth: 4, contentHeight: 4)
            return RegionCommands.setScroll(scroll?.clamped(to: region.frame), of: region.id, scrollOffsets: offsets)
        default:
            return RegionCommands.setTitle("Edited \(random.int(0...999))", of: region.id)
        }
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
        XCTAssertEqual(project.screens.map(\.name).prefix(3), ["Login", "Login (Desktop)", "Login Copy"])
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
