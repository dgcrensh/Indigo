import XCTest

@testable import DescriberCore

/// Spec Section 8 in the core: sidebar order, the screen and variant commands, names, the delete question,
/// navigation, link targets and the link history.
final class ScreenManagementTests: XCTestCase {
    private let login = AcmeExample.login
    private let loginDesktop = AcmeExample.loginDesktop
    private let reset = AcmeExample.resetPassword
    private let settings = AcmeExample.settings
    private let accountMenu = AcmeExample.accountMenu

    // MARK: Sidebar order

    func testTheSidebarShowsAHeaderAboveEachGroup() {
        let outline = SidebarOutline(project: AcmeExample.make())
        XCTAssertEqual(
            outline.rows,
            [
                .group(0), .screen(login, group: 0), .screen(loginDesktop, group: 0), .screen(reset, group: nil),
                .screen(settings, group: nil), .screen(accountMenu, group: nil),
            ])
        XCTAssertEqual(outline.screens, [login, loginDesktop, reset, settings, accountMenu])
    }

    func testAGroupSplitInTheFileIsShownTogether() {
        let project = AcmeExample.make()
        project.screens.swapAt(1, 3)
        XCTAssertEqual(project.screens.map(\.id), [login, settings, reset, loginDesktop, accountMenu])
        XCTAssertEqual(SidebarOutline(project: project).screens, [login, loginDesktop, settings, reset, accountMenu])
    }

    func testDraggingAScreenIntoAGroupItIsNotInPutsItAfterTheGroup() {
        let outline = SidebarOutline(project: AcmeExample.make())
        // Settings (row 4) dropped between Login and Login (Desktop).
        XCTAssertEqual(
            outline.order(afterMoving: [4], to: 2), [login, loginDesktop, settings, reset, accountMenu])
        // Dropped above the group's header, it goes first.
        XCTAssertEqual(
            outline.order(afterMoving: [4], to: 0), [settings, login, loginDesktop, reset, accountMenu])
    }

    func testDraggingAGroupsScreenAwayTakesTheGroupAlong() {
        let outline = SidebarOutline(project: AcmeExample.make())
        XCTAssertEqual(
            outline.order(afterMoving: [1], to: 6), [reset, settings, accountMenu, loginDesktop, login])
    }

    func testDraggingWithinAGroupReordersIt() {
        let outline = SidebarOutline(project: AcmeExample.make())
        XCTAssertEqual(
            outline.order(afterMoving: [1], to: 3), [loginDesktop, login, reset, settings, accountMenu])
        XCTAssertEqual(
            outline.order(afterMoving: [0], to: 6), outline.screens, "a header row can't be dragged")
    }

    // MARK: Commands

    func testReorderScreensKeepsGroupsTogetherAndRefusesNoChange() throws {
        let project = AcmeExample.make()
        _ = try ReorderScreens([login, settings, loginDesktop, reset, accountMenu]).apply(to: project)
        XCTAssertEqual(project.screens.map(\.id), [login, loginDesktop, settings, reset, accountMenu])
        XCTAssertThrowsError(try ReorderScreens(project.screens.map(\.id)).apply(to: project)) {
            XCTAssertEqual($0 as? EditError, .nothingToDo)
        }
        XCTAssertThrowsError(try ReorderScreens([login]).apply(to: project))
    }

    func testJoiningAScreenWithoutAGroupMakesOneNamedAfterTheTarget() throws {
        let project = AcmeExample.make()
        _ = try JoinVariants(accountMenu, joining: reset).apply(to: project)
        XCTAssertEqual(project.variantGroups.last, VariantGroup(name: "Reset Password", screens: [reset, accountMenu]))
        XCTAssertEqual(project.screens.map(\.id), [login, loginDesktop, reset, accountMenu, settings])
    }

    func testJoiningAGroupLeavesTheOldOneAndDissolvesItWhenOneIsLeft() throws {
        let project = AcmeExample.make()
        _ = try JoinVariants(loginDesktop, joining: settings).apply(to: project)
        XCTAssertEqual(project.variantGroups, [VariantGroup(name: "Settings", screens: [settings, loginDesktop])])
        XCTAssertEqual(project.screens.map(\.id), [login, reset, settings, loginDesktop, accountMenu])

        _ = try JoinVariants(accountMenu, joining: loginDesktop).apply(to: project)
        XCTAssertEqual(
            project.variantGroups, [VariantGroup(name: "Settings", screens: [settings, loginDesktop, accountMenu])])
        XCTAssertThrowsError(try JoinVariants(accountMenu, joining: settings).apply(to: project)) {
            XCTAssertEqual($0 as? EditError, .nothingToDo)
        }
        XCTAssertThrowsError(try JoinVariants(reset, joining: reset).apply(to: project))
    }

    func testLeavingAGroupPutsTheScreenAfterIt() throws {
        let project = AcmeExample.make()
        _ = try JoinVariants(reset, joining: login).apply(to: project)
        XCTAssertEqual(project.screens.map(\.id), [login, loginDesktop, reset, settings, accountMenu])
        _ = try LeaveVariantGroup(login).apply(to: project)
        XCTAssertEqual(project.variantGroups, [VariantGroup(name: "Login", screens: [loginDesktop, reset])])
        XCTAssertEqual(project.screens.map(\.id), [loginDesktop, reset, login, settings, accountMenu])

        _ = try LeaveVariantGroup(reset).apply(to: project)
        XCTAssertEqual(project.variantGroups, [], "a group left with one screen is dissolved")
        XCTAssertThrowsError(try LeaveVariantGroup(settings).apply(to: project))
    }

    func testRenamingAGroup() throws {
        let project = AcmeExample.make()
        _ = try RenameVariantGroup(containing: loginDesktop, to: "Sign in").apply(to: project)
        XCTAssertEqual(project.variantGroups[0].name, "Sign in")
        XCTAssertThrowsError(try RenameVariantGroup(containing: settings, to: "x").apply(to: project))
    }

    func testANewOrDuplicatedScreenInsideAGroupGoesAfterIt() throws {
        let project = AcmeExample.make()
        let add = AddScreen(name: "Onboarding", viewport: .defaultForNewScreens, at: 1)
        _ = try add.apply(to: project)
        XCTAssertEqual(project.screens.map(\.id), [login, loginDesktop, add.screen.id, reset, settings, accountMenu])

        let duplicate = DuplicateScreen(login)
        _ = try duplicate.apply(to: project)
        XCTAssertEqual(project.screens.map(\.id)[2], duplicate.newID)
    }

    func testGroupingScreensMovesThemTogether() throws {
        let project = AcmeExample.make()
        _ = try GroupVariants([reset, accountMenu], name: "Odd pair").apply(to: project)
        XCTAssertEqual(project.screens.map(\.id), [login, loginDesktop, reset, accountMenu, settings])
    }

    func testTheOnlyScreenCantBeDeleted() {
        let (project, screen) = Fixtures.simpleProject()
        XCTAssertThrowsError(try DeleteScreen(screen.id).apply(to: project)) {
            XCTAssertEqual($0 as? EditError, .nothingToDo)
        }
        XCTAssertEqual(project.screens.count, 1)
    }

    // MARK: Names and the delete question

    func testNewScreenNamesCountUpPastNamesInUse() {
        let (project, screen) = Fixtures.simpleProject()
        XCTAssertEqual(ScreenNames.newScreenName(in: project), "Screen 1")
        screen.name = "screen 1"
        project.screens.append(Screen(name: "Screen 2", viewport: .defaultForNewScreens))
        XCTAssertEqual(ScreenNames.newScreenName(in: project), "Screen 3")
    }

    func testABlankRenameIsRefused() {
        XCTAssertEqual(ScreenNames.cleaned("  Profile \n"), "Profile")
        XCTAssertNil(ScreenNames.cleaned(" \n "))
    }

    func testDeletingALinkedScreenAsksAndCountsTheLinkingRegions() {
        let project = AcmeExample.make()
        XCTAssertEqual(
            ScreenDeleteConfirmation.message(deleting: reset, in: project),
            "Delete “Reset Password”? 2 regions on other screens link to it, and those links will be removed.")
        XCTAssertNil(ScreenDeleteConfirmation.message(deleting: loginDesktop, in: project), "nothing links to it")
    }

    // MARK: Navigation

    func testNextAndPreviousScreenFollowTheSidebarAndStopAtTheEnds() {
        let project = AcmeExample.make()
        XCTAssertEqual(ScreenNavigation.neighbor(of: login, offset: 1, in: project), loginDesktop)
        XCTAssertEqual(ScreenNavigation.neighbor(of: settings, offset: -1, in: project), reset)
        XCTAssertNil(ScreenNavigation.neighbor(of: login, offset: -1, in: project))
        XCTAssertNil(ScreenNavigation.neighbor(of: accountMenu, offset: 1, in: project))
        XCTAssertEqual(ScreenNavigation.neighbor(of: nil, offset: 1, in: project), login)
    }

    func testARemovedScreensPlaceGoesToTheScreenAfterItOrElseBefore() {
        let project = AcmeExample.make()
        let order = SidebarOutline(project: project).screens
        project.screens.removeAll { $0.id == reset }
        XCTAssertEqual(ScreenNavigation.replacement(forRemoved: reset, previousOrder: order, in: project), settings)
        project.screens.removeAll { $0.id == accountMenu }
        XCTAssertEqual(
            ScreenNavigation.replacement(forRemoved: accountMenu, previousOrder: order, in: project), settings)
    }

    func testLinkTargetsNameTheScreenAndTrigger() throws {
        let project = AcmeExample.make()
        let forgot = try XCTUnwrap(project.region(withID: RegionID("8e81973e-0bec-47b0-b898-d190f9ebdacc"))?.region)
        XCTAssertEqual(
            LinkTargets.entries(for: forgot, in: project), [LinkTarget(screen: reset, title: "Reset Password — click")])

        forgot.links = [Link(screen: settings), Link(screen: ScreenID("missing")), Link(screen: login, trigger: " ")]
        XCTAssertEqual(LinkTargets.entries(for: forgot, in: project).map(\.title), ["Settings", "Login"])
    }

    func testHistoryGoesBackAndForwardLikeABrowser() {
        let project = AcmeExample.make()
        var history = NavigationHistory()
        XCTAssertFalse(history.canGoBack(from: login, in: project))

        history.visit(reset, from: login)
        history.visit(settings, from: reset)
        XCTAssertTrue(history.canGoBack(from: settings, in: project))
        XCTAssertEqual(history.back(from: settings, in: project), reset)
        XCTAssertEqual(history.back(from: reset, in: project), login)
        XCTAssertNil(history.back(from: login, in: project))
        XCTAssertEqual(history.forward(from: login, in: project), reset)
        XCTAssertTrue(history.canGoForward(from: reset, in: project))

        // Following a new link clears Forward.
        history.visit(accountMenu, from: reset)
        XCTAssertFalse(history.canGoForward(from: accountMenu, in: project))
        XCTAssertEqual(history.back(from: accountMenu, in: project), reset)
    }

    func testHistorySkipsDeletedScreens() {
        let project = AcmeExample.make()
        var history = NavigationHistory()
        history.visit(reset, from: login)
        history.visit(settings, from: reset)
        project.screens.removeAll { $0.id == reset }
        XCTAssertEqual(history.back(from: settings, in: project), login)
    }

    func testFollowingALinkToTheShownScreenChangesNothing() {
        var history = NavigationHistory()
        history.visit(login, from: login)
        XCTAssertEqual(history, NavigationHistory())
    }
}
