import XCTest

@testable import DescriberCore

final class RegionEditorTests: XCTestCase {
    private typealias Nested = (project: Project, screen: Screen, outer: Region, inner: Region, side: Region)

    private func create(_ fixture: Nested, in session: EditSession) throws -> RegionEditor {
        try RegionEditor(
            creating: CreateRegion(screen: fixture.screen.id, frame: Frame(x: 40, y: 40, w: 40, h: 40)),
            in: session)
    }

    // MARK: Edit session

    func testChangesAppliedWithoutRecordingBecomeOneStepWhenRecorded() throws {
        let fixture = Fixtures.nestedProject()
        let session = EditSession(project: fixture.project)
        let first = try session.applyWithoutRecording(RegionCommands.setTitle("A", of: fixture.side.id))
        XCTAssertEqual(session.undoDepth, 0)
        XCTAssertEqual(fixture.side.title, "A")

        session.record(first)
        XCTAssertEqual(session.undoDepth, 1)
        try session.undo()
        XCTAssertEqual(fixture.side.title, "Side")
        try session.redo()
        XCTAssertEqual(fixture.side.title, "A")
    }

    func testRecordingClearsRedo() throws {
        let fixture = Fixtures.nestedProject()
        let session = EditSession(project: fixture.project)
        try session.perform(RegionCommands.setTitle("A", of: fixture.side.id))
        try session.undo()
        XCTAssertTrue(session.canRedo)
        session.record(try session.applyWithoutRecording(RegionCommands.setTitle("B", of: fixture.side.id)))
        XCTAssertFalse(session.canRedo)
    }

    // MARK: New regions

    func testANewRegionWithATitleIsOneNewRegionStep() throws {
        let fixture = Fixtures.nestedProject()
        let session = EditSession(project: fixture.project)
        let before = Fixtures.bytes(fixture.project)
        let editor = try create(fixture, in: session)
        XCTAssertTrue(editor.isNew)
        XCTAssertEqual(editor.fields.title, "")
        XCTAssertEqual(RegionIndex(screen: fixture.screen).parent(of: editor.region)?.id, fixture.inner.id)

        try editor.setTitle("  Avatar ")
        try editor.setDescription("Round photo.")
        try editor.setKind(.image)
        XCTAssertEqual(session.project.region(withID: editor.region)?.region.title, "  Avatar ", "changes show at once")
        XCTAssertEqual(session.undoDepth, 0)

        XCTAssertEqual(editor.commit(), .recorded(actionName: "New Region"))
        XCTAssertEqual(session.undoDepth, 1)
        let region = try XCTUnwrap(session.project.region(withID: editor.region)?.region)
        XCTAssertEqual(RegionFields(region), RegionFields(title: "Avatar", description: "Round photo.", kind: .image))
        let after = Fixtures.bytes(fixture.project)

        try session.undo()
        XCTAssertEqual(Fixtures.bytes(fixture.project), before)
        try session.redo()
        XCTAssertEqual(Fixtures.bytes(fixture.project), after, "redo brings the region back with its fields")
    }

    func testANewRegionWithABlankTitleIsDiscarded() throws {
        for title in ["", "  \n "] {
            let fixture = Fixtures.nestedProject()
            let session = EditSession(project: fixture.project)
            let before = Fixtures.bytes(fixture.project)
            let editor = try create(fixture, in: session)
            try editor.setTitle(title)
            try editor.setDescription("Kept only with a title.")
            XCTAssertEqual(editor.commit(), .discarded)
            XCTAssertNil(session.project.region(withID: editor.region))
            XCTAssertEqual(Fixtures.bytes(fixture.project), before)
            XCTAssertEqual(session.undoDepth, 0)
        }
    }

    func testCancellingANewRegionRemovesIt() throws {
        let fixture = Fixtures.nestedProject()
        let session = EditSession(project: fixture.project)
        let editor = try create(fixture, in: session)
        try editor.setTitle("Avatar")
        editor.cancel()
        XCTAssertNil(session.project.region(withID: editor.region))
        XCTAssertEqual(session.undoDepth, 0)
    }

    // MARK: Existing regions

    func testAClearedTitleRevertsAndABlankDescriptionIsKept() throws {
        let fixture = Fixtures.nestedProject()
        fixture.side.description = "Old"
        let session = EditSession(project: fixture.project)
        let editor = try RegionEditor(region: fixture.side.id, in: session)
        XCTAssertFalse(editor.isNew)
        try editor.setTitle(" ")
        try editor.setDescription("")
        XCTAssertEqual(editor.commit(), .recorded(actionName: "Edit Description"))
        XCTAssertEqual(fixture.side.title, "Side")
        XCTAssertEqual(fixture.side.description, "")
        try session.undo()
        XCTAssertEqual(fixture.side.description, "Old")
    }

    func testAnUnchangedSessionRecordsNothing() throws {
        let fixture = Fixtures.nestedProject()
        let session = EditSession(project: fixture.project)
        let editor = try RegionEditor(region: fixture.side.id, in: session)
        try editor.setTitle("Other")
        try editor.setTitle("Side")
        XCTAssertEqual(editor.commit(), .unchanged)
        XCTAssertEqual(session.undoDepth, 0)
    }

    func testOneChangedFieldNamesTheStepAfterIt() throws {
        let fixture = Fixtures.nestedProject()
        let session = EditSession(project: fixture.project)
        let editor = try RegionEditor(region: fixture.side.id, in: session)
        try editor.setKind(.button)
        XCTAssertEqual(editor.commit(), .recorded(actionName: "Change Kind"))
    }

    func testSeveralChangedFieldsAreOneEditRegionStep() throws {
        let fixture = Fixtures.nestedProject()
        let other = Screen(name: "Other", viewport: Viewport(width: 100, height: 100))
        fixture.project.screens.append(other)
        let session = EditSession(project: fixture.project)
        let before = Fixtures.bytes(fixture.project)
        let editor = try RegionEditor(region: fixture.side.id, in: session)
        try editor.setTitle("Next")
        try editor.setDescription("Goes on.")
        try editor.setKind(.button)
        try editor.setLinks([Link(screen: other.id, trigger: "click")])
        try editor.setScroll(Scroll.defaultFor(fixture.side.frame))
        XCTAssertEqual(editor.commit(), .recorded(actionName: "Edit Region"))
        XCTAssertEqual(session.undoDepth, 1)
        let after = Fixtures.bytes(fixture.project)

        try session.undo()
        XCTAssertEqual(Fixtures.bytes(fixture.project), before)
        try session.redo()
        XCTAssertEqual(Fixtures.bytes(fixture.project), after)
    }

    func testCancellingPutsEveryFieldBack() throws {
        let fixture = Fixtures.nestedProject()
        let session = EditSession(project: fixture.project)
        let before = Fixtures.bytes(fixture.project)
        let editor = try RegionEditor(region: fixture.side.id, in: session)
        try editor.setTitle("Next")
        try editor.setKind(.list)
        editor.cancel()
        XCTAssertEqual(Fixtures.bytes(fixture.project), before)
        XCTAssertEqual(session.undoDepth, 0)
        XCTAssertEqual(editor.commit(), .unchanged, "a finished session records nothing more")
    }

    func testARegionRemovedWhileOpenIsDiscarded() throws {
        let fixture = Fixtures.nestedProject()
        let session = EditSession(project: fixture.project)
        let editor = try RegionEditor(region: fixture.side.id, in: session)
        try editor.setTitle("Next")
        _ = try session.applyWithoutRecording(DeleteRegions(screen: fixture.screen.id, regions: [fixture.side.id]))
        XCTAssertFalse(editor.regionExists)
        XCTAssertEqual(editor.commit(), .discarded)
        XCTAssertEqual(session.undoDepth, 0)
    }

    func testOpeningAMissingRegionThrows() {
        let fixture = Fixtures.nestedProject()
        XCTAssertThrowsError(try RegionEditor(region: RegionID("nope"), in: EditSession(project: fixture.project)))
    }

    // MARK: Helpers

    func testNewLinksPointAtAnotherScreenWhenThereIsOne() throws {
        let fixture = Fixtures.nestedProject()
        let editor = try RegionEditor(region: fixture.side.id, in: EditSession(project: fixture.project))
        XCTAssertEqual(editor.newLinkTarget(in: fixture.project), fixture.screen.id)
        let other = Screen(name: "Other", viewport: Viewport(width: 100, height: 100))
        fixture.project.screens.append(other)
        XCTAssertEqual(editor.newLinkTarget(in: fixture.project), other.id)
    }

    func testKindsHaveDisplayNames() {
        XCTAssertEqual(RegionKind.open.displayName, "Open")
        XCTAssertEqual(RegionKind.menuItem.displayName, "Menu Item")
        XCTAssertEqual(Set(RegionKind.allCases.map(\.displayName)).count, RegionKind.allCases.count)
        XCTAssertEqual(ScrollAxis.both.displayName, "Both")
    }

    func testScrollDefaultsAndClamping() {
        let frame = Frame(x: 0, y: 0, w: 100, h: 60)
        XCTAssertEqual(Scroll.defaultFor(frame), Scroll(axis: .vertical, contentWidth: 100, contentHeight: 120))
        XCTAssertEqual(
            Scroll(axis: .horizontal, contentWidth: 20, contentHeight: 300).clamped(to: frame),
            Scroll(axis: .horizontal, contentWidth: 100, contentHeight: 300))
    }
}
