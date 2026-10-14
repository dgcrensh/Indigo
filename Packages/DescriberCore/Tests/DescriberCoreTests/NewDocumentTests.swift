import XCTest

@testable import DescriberCore

final class NewDocumentTests: XCTestCase {
    func testUntitledProjectHasOneScreenAtTheDefaultViewport() throws {
        let project = Project.untitled()
        XCTAssertEqual(project.name, "Untitled")
        XCTAssertEqual(project.screens.count, 1)
        let screen = try XCTUnwrap(project.screens.first)
        XCTAssertEqual(screen.name, "Screen 1")
        XCTAssertEqual(screen.kind, .screen)
        XCTAssertEqual(screen.viewport, Viewport(preset: "iphone-15", width: 393, height: 852))
        XCTAssertEqual(screen.viewport, .defaultForNewScreens)
        XCTAssertTrue(screen.regions.isEmpty)
    }

    func testUntitledProjectRoundTripsThroughThePackageFormat() throws {
        let tree = ProjectPackage.write(project: Project.untitled()).tree
        XCTAssertEqual(Set(tree.keys), ["project.json", "screens/screen-1.json"])
        let reread = try ProjectPackage.read(tree)
        XCTAssertEqual(ProjectPackage.write(project: reread).tree, tree)
    }

    func testInitialScreenPrefersTheLastActiveScreen() {
        let project = AcmeExample.make()
        project.editorState.lastActiveScreen = AcmeExample.settings
        XCTAssertEqual(project.initialScreen, AcmeExample.settings)
    }

    func testInitialScreenFallsBackToTheFirstScreen() {
        let project = AcmeExample.make()
        XCTAssertEqual(project.initialScreen, AcmeExample.login)
        project.editorState.lastActiveScreen = ScreenID.make()
        XCTAssertEqual(project.initialScreen, AcmeExample.login)
    }

    func testInitialScreenIsNilWithoutScreens() {
        XCTAssertNil(Project(name: "Empty").initialScreen)
    }
}
