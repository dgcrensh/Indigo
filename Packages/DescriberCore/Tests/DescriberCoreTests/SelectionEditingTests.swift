import DescriberCore
import XCTest

/// Spec Section 7: building the selection, the clipboard, reordering, nudging, delete confirmation, and showing
/// descriptions.
final class SelectionEditingTests: XCTestCase {
    private let form = RegionID("90c192cf-d3ac-44af-8f21-ddb66cad4a26")
    private let email = RegionID("a170b338-3926-4059-b28c-105d1fb17c23")
    private let password = RegionID("0fd630f1-f29d-4da9-953f-48f1a09f76b5")
    private let logo = RegionID("8d116ece-1738-47d9-bd9c-172411e20b8f")
    private let signIn = RegionID("0cb1e29c-658c-4a14-95e6-0af593bd04cf")

    private func login(_ project: Project) throws -> Screen {
        try XCTUnwrap(project.screen(withID: AcmeExample.login))
    }

    // MARK: Selecting

    func testSelectAllListsEveryRegionInDrawOrder() throws {
        let (_, screen, outer, inner, side) = Fixtures.nestedProject()
        XCTAssertEqual(Selection.all(on: screen), [outer.id, inner.id, side.id])
    }

    func testSelectParentReachesAParentCoveredByItsChildren() throws {
        // A parent whose child covers it entirely can't be clicked, only reached from the child.
        let child = Region(id: RegionID("child"), title: "Child", frame: Frame(x: 0, y: 0, w: 100, h: 100))
        let parent = Region(
            id: RegionID("parent"), title: "Parent", frame: Frame(x: 0, y: 0, w: 100, h: 100), children: [child])
        let screen = Screen(name: "S", viewport: Viewport(width: 400, height: 400), regions: [parent])
        XCTAssertEqual(Selection.parents(of: [child.id], on: screen), [parent.id])
    }

    func testSelectParentOfSeveralRegionsAndOfTopLevelRegions() throws {
        let project = AcmeExample.make()
        let screen = try login(project)
        XCTAssertEqual(Selection.parents(of: [email, password], on: screen), [form], "one parent, no repeats")
        XCTAssertEqual(Selection.parents(of: [logo], on: screen), [], "a top-level region has no parent")
        XCTAssertEqual(Selection.parents(of: [logo, email], on: screen), [form])
        XCTAssertEqual(Selection.parents(of: [], on: screen), [])
    }

    func testSelectChildrenGivesDirectChildrenOnly() throws {
        let (_, screen, outer, inner, side) = Fixtures.nestedProject()
        let grandchild = Region(id: RegionID("grand"), title: "Grand", frame: Frame(x: 30, y: 30, w: 10, h: 10))
        inner.children = [grandchild]
        XCTAssertEqual(Selection.children(of: [outer.id], on: screen), [inner.id])
        XCTAssertEqual(Selection.children(of: [outer.id, inner.id], on: screen), [inner.id, grandchild.id])
        XCTAssertEqual(Selection.children(of: [side.id], on: screen), [])
    }

    // MARK: Clipboard

    func testCopiedRegionsReadBackFromTheirData() throws {
        let project = AcmeExample.make()
        let screen = try login(project)
        let clipboard = try XCTUnwrap(RegionClipboard(copying: [form], on: screen))
        let read = try RegionClipboard(data: clipboard.data(in: project))
        XCTAssertEqual(read.sourceScreen, AcmeExample.login)
        XCTAssertEqual(read.regions.count, 1)
        let original = try XCTUnwrap(project.region(withID: form)?.region)
        XCTAssertEqual(read.regions[0].subtree.map(\.id), original.subtree.map(\.id))
        XCTAssertEqual(read.regions[0].subtree.map(\.frame), original.subtree.map(\.frame))
        XCTAssertEqual(read.regions[0].subtree.map(\.description), original.subtree.map(\.description))
        XCTAssertEqual(read.regions[0].subtree.map(\.links), original.subtree.map(\.links))
        XCTAssertEqual(read.text, "Sign-in form")
    }

    func testBadClipboardDataThrows() {
        XCTAssertThrowsError(try RegionClipboard(data: Data("{\"regions\": 3}".utf8)))
        XCTAssertThrowsError(try RegionClipboard(data: Data("{\"screen\": \"s\", \"regions\": []}".utf8)))
        XCTAssertThrowsError(try RegionClipboard(data: Data("not json".utf8)))
    }

    func testCopyingAParentAndItsChildCopiesTheChildOnceInDrawOrder() throws {
        let project = AcmeExample.make()
        let screen = try login(project)
        let clipboard = try XCTUnwrap(RegionClipboard(copying: [email, form, logo], on: screen))
        XCTAssertEqual(clipboard.regions.map(\.id), [logo, form])
        XCTAssertNil(RegionClipboard(copying: [], on: screen))
        XCTAssertNil(RegionClipboard(copying: [RegionID("missing")], on: screen))
    }

    func testPastingOntoTheSourceScreenMovesOneGridStepEachTime() throws {
        let project = AcmeExample.make()
        let session = EditSession(project: project)
        let screen = try login(project)
        let clipboard = try XCTUnwrap(RegionClipboard(copying: [logo], on: screen))

        let first = clipboard.paste(onto: screen, in: project, grid: 8)
        try session.perform(first)
        XCTAssertEqual(first.pasted.first?.frame, Frame(x: 156, y: 104, w: 96, h: 96))
        let second = clipboard.paste(onto: screen, in: project, grid: 8)
        try session.perform(second)
        XCTAssertEqual(second.pasted.first?.frame, Frame(x: 164, y: 112, w: 96, h: 96))
        XCTAssertEqual(first.actionName, "Paste")
        XCTAssertNotEqual(first.pasted.first?.id, logo)
    }

    func testPastingOntoAnotherScreenKeepsFramesAndDropsMissingLinkTargets() throws {
        let source = AcmeExample.make()
        let clipboard = try XCTUnwrap(RegionClipboard(copying: [form], on: try login(source)))
        let project = AcmeExample.make()
        let reset = try XCTUnwrap(project.screen(withID: AcmeExample.resetPassword))

        let paste = clipboard.paste(onto: reset, in: project, grid: 8)
        try EditSession(project: project).perform(paste)
        let pasted = try XCTUnwrap(paste.pasted.first)
        XCTAssertEqual(pasted.frame, Frame(x: 16, y: 240, w: 361, h: 264))
        XCTAssertTrue(Set(pasted.subtree.map(\.id)).isDisjoint(with: clipboard.regions[0].subtree.map(\.id)))
        XCTAssertEqual(pasted.subtree.map(\.links), clipboard.regions[0].subtree.map(\.links))

        // Another document without the Settings screen keeps only the link it can follow.
        let other = AcmeExample.make()
        other.screens.removeAll { $0.id == AcmeExample.settings }
        let otherReset = try XCTUnwrap(other.screen(withID: AcmeExample.resetPassword))
        let pastedElsewhere = try XCTUnwrap(clipboard.paste(onto: otherReset, in: other, grid: 8).pasted.first)
        let button = try XCTUnwrap(pastedElsewhere.subtree.first { $0.title == "Sign in" })
        XCTAssertEqual(button.links, [])
        let forgot = try XCTUnwrap(pastedElsewhere.subtree.first { $0.title == "Forgot password" })
        XCTAssertEqual(forgot.links, [Link(screen: AcmeExample.resetPassword, trigger: "click")])
    }

    func testDuplicateIsNamedForTheMenu() throws {
        let (project, screen, _, inner, _) = Fixtures.nestedProject()
        let clipboard = try XCTUnwrap(RegionClipboard(copying: [inner.id], on: screen))
        let duplicate = clipboard.paste(onto: screen, in: project, grid: 8, actionName: "Duplicate")
        let session = EditSession(project: project)
        try session.perform(duplicate)
        XCTAssertEqual(session.undoActionName, "Duplicate")
        XCTAssertEqual(Fixtures.outline(screen), ["Outer", "  Inner", "  Inner", "Side"], "the copy stays inside")
    }

    // MARK: Reordering

    func testBringingSeveralRegionsToTheFrontKeepsTheirOrder() throws {
        let regions = (0..<4).map {
            Region(id: RegionID("r\($0)"), title: "R\($0)", frame: Frame(x: $0 * 10, y: 0, w: 50, h: 50))
        }
        let screen = Screen(id: ScreenID("s"), name: "S", viewport: Viewport(width: 400, height: 400), regions: regions)
        let project = Project(name: "P", screens: [screen])
        let session = EditSession(project: project)

        try session.perform(ReorderRegions(screen: screen.id, regions: [regions[2].id, regions[0].id], to: .front))
        XCTAssertEqual(screen.regions.map(\.title), ["R1", "R3", "R0", "R2"])
        XCTAssertEqual(session.undoActionName, "Bring to Front")
        try session.perform(ReorderRegions(screen: screen.id, regions: [regions[2].id, regions[3].id], to: .back))
        XCTAssertEqual(screen.regions.map(\.title), ["R3", "R2", "R1", "R0"])
        try session.undo()
        try session.undo()
        XCTAssertEqual(screen.regions.map(\.title), ["R0", "R1", "R2", "R3"])
    }

    func testReorderingRegionsInDifferentParentsStaysWithinEachParent() throws {
        let project = AcmeExample.make()
        let screen = try login(project)
        _ = try ReorderRegions(screen: screen.id, regions: [email, logo], to: .front).apply(to: project)
        XCTAssertEqual(screen.regions.map(\.title), ["Sign-in form", "Footer", "Logo"])
        let formRegion = try XCTUnwrap(project.region(withID: form)?.region)
        XCTAssertEqual(
            formRegion.children.map(\.title), ["Password field", "Sign in", "Forgot password", "Email field"])
    }

    func testReorderingRegionsAlreadyInPlaceThrows() throws {
        let (project, screen, _, _, side) = Fixtures.nestedProject()
        XCTAssertThrowsError(try ReorderRegions(screen: screen.id, regions: [side.id], to: .front).apply(to: project)) {
            XCTAssertEqual($0 as? EditError, .nothingToDo)
        }
        XCTAssertThrowsError(
            try ReorderRegions(screen: screen.id, regions: [RegionID("missing")], to: .back).apply(to: project))
    }

    // MARK: Nudging

    func testNudgeDeltas() {
        XCTAssertEqual(Nudge.delta(for: .nudgeLeft, grid: 8, snapping: true)?.dx, -8)
        XCTAssertEqual(Nudge.delta(for: .nudgeDown, grid: 8, snapping: true)?.dy, 8)
        XCTAssertEqual(Nudge.delta(for: .nudgeRightFar, grid: 8, snapping: true)?.dx, 32)
        XCTAssertEqual(Nudge.delta(for: .nudgeUpFar, grid: 12, snapping: true)?.dy, -48)
        XCTAssertEqual(Nudge.delta(for: .nudgeUp, grid: 8, snapping: false)?.dy, -1)
        XCTAssertEqual(Nudge.delta(for: .nudgeLeftFar, grid: 8, snapping: false)?.dx, -4)
        XCTAssertEqual(Nudge.delta(for: .nudgeRight, grid: 8, snapping: true)?.dy, 0)
        XCTAssertNil(Nudge.delta(for: .delete, grid: 8, snapping: true))
    }

    // MARK: Deleting

    func testDeleteConfirmationNamesTheRegionAndCountsWhatIsInside() throws {
        let project = AcmeExample.make()
        let screen = try login(project)
        XCTAssertEqual(
            DeleteConfirmation.message(deleting: [form], on: screen),
            "Delete “Sign-in form” and the 4 regions inside it?")
        XCTAssertEqual(
            DeleteConfirmation.message(deleting: [form, email], on: screen),
            "Delete “Sign-in form” and the 4 regions inside it?", "a selected child counts as inside")
        XCTAssertEqual(
            DeleteConfirmation.message(deleting: [logo, form], on: screen),
            "Delete 2 regions and the 4 regions inside them?")
        XCTAssertNil(DeleteConfirmation.message(deleting: [logo, email], on: screen))
        XCTAssertNil(DeleteConfirmation.message(deleting: [], on: screen))

        let (_, nested, outer, _, _) = Fixtures.nestedProject()
        outer.title = " "
        XCTAssertEqual(
            DeleteConfirmation.message(deleting: [outer.id], on: nested),
            "Delete this region and the region inside it?")
    }

    // MARK: Descriptions

    func testTogglingDescriptionsShowsAllUnlessAllAreShown() {
        let a = RegionID("a")
        let b = RegionID("b")
        let c = RegionID("c")
        XCTAssertEqual(DescriptionVisibility.toggling([a, b], in: [b, c]), [a, b, c])
        XCTAssertEqual(DescriptionVisibility.toggling([a, b], in: [a, b, c]), [c])
        XCTAssertEqual(DescriptionVisibility.toggling([], in: [c]), [c])
    }
}
