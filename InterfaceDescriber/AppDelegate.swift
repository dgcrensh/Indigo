import AppKit
import DescriberCore

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.mainMenu = MainMenu.make()
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate()
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        true
    }

    #if DEBUG
        /// Opens an untitled document holding the 500-region stress project, for checking the canvas by hand.
        @MainActor
        @objc func newStressTestDocument(_ sender: Any?) {
            let document = Document()
            document.fileType = AppIdentity.documentTypeIdentifier
            document.model.replaceProject(with: .stressTest(regionCount: 500))
            NSDocumentController.shared.addDocument(document)
            document.makeWindowControllers()
            document.showWindows()
        }
    #endif
}
