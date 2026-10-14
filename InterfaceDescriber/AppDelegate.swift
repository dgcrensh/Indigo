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

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = SettingsStore.shared
        NotificationCenter.default.addObserver(
            self, selector: #selector(settingsDidChange(_:)), name: SettingsStore.didChangeNotification,
            object: settings)
        settings.startWatching()
        applyKeybinds()
        NSApp.activate()
    }

    // MARK: Settings

    @MainActor
    @objc private func settingsDidChange(_ notification: Notification) {
        applyKeybinds()
    }

    /// Gives the menu bar the keys from settings.
    @MainActor
    private func applyKeybinds() {
        guard let menu = NSApp.mainMenu else { return }
        MainMenu.applyKeybinds(SettingsStore.shared.settings.keybinds, to: menu)
    }

    /// Opens `settings.json` in the app the Mac uses for JSON files, creating it as `{}` when there is none, or shows
    /// it in Finder when no app opens it.
    @MainActor
    @objc func openSettings(_ sender: Any?) {
        let settings = SettingsStore.shared
        do {
            try settings.createFileIfMissing()
        } catch {
            NSApp.presentError(error)
            return
        }
        let url = settings.url
        NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            guard error != nil else { return }
            DispatchQueue.main.async {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
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
