import DescriberCore
import Foundation
import Observation

/// The app settings in `settings.json` in the app's Application Support folder (spec 3 and 12). Watches the file and
/// reads it again whenever it changes, so hand edits apply without a relaunch. A file that can't be read keeps the
/// settings from before and sets `error`; the store never writes such a file. Used on the main thread only, where
/// the watcher delivers its events.
@Observable
final class SettingsStore {
    /// Posted after the settings or the error change, with the store as the object.
    static let didChangeNotification = Notification.Name("SettingsStoreDidChange")
    /// How long the watcher waits after the last change to the file before reading it, so an editor's writes settle.
    static let settleDelay: TimeInterval = 0.1

    /// The app's settings. While the app hosts its unit tests it uses a file in a temporary folder instead, so tests
    /// never read or write the user's settings.
    static let shared = SettingsStore(url: isHostingTests ? testURL : defaultURL)

    private static var isHostingTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        return ["XCTestConfigurationFilePath", "XCTestBundlePath", "XCTestSessionIdentifier"].contains {
            environment[$0] != nil
        }
    }

    /// A `settings.json` in a temporary folder of this process's own.
    static var testURL: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("InterfaceDescriberTests-\(ProcessInfo.processInfo.processIdentifier)")
            .appendingPathComponent(SettingsFile.fileName)
    }

    /// `~/Library/Application Support/Interface Describer/settings.json`.
    static var defaultURL: URL {
        let support =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent(AppIdentity.appName).appendingPathComponent(SettingsFile.fileName)
    }

    let url: URL
    private(set) var settings = AppSettings.defaults
    /// Why the file couldn't be used the last time it was read, if it couldn't. The settings from before are kept.
    private(set) var error: Error?

    /// The contents last read, so an event that changed nothing doesn't read the file again.
    @ObservationIgnored private var lastContents: Data??
    @ObservationIgnored private var folderSource: DispatchSourceFileSystemObject?
    @ObservationIgnored private var fileSource: DispatchSourceFileSystemObject?
    @ObservationIgnored private var pendingRead: DispatchWorkItem?

    init(url: URL) {
        self.url = url
        reload()
    }

    /// Reads the file again. A missing file is the defaults; a file that can't be used leaves the settings as they
    /// were and sets `error`.
    func reload() {
        let contents: Data?
        do {
            contents = try self.contents()
        } catch {
            update(settings: nil, error: error)
            return
        }
        if let lastContents, lastContents == contents { return }
        lastContents = contents
        do {
            update(settings: try SettingsFile.settings(in: contents), error: nil)
        } catch {
            update(settings: nil, error: error)
        }
    }

    private func update(settings newSettings: AppSettings?, error newError: Error?) {
        let settingsChanged = newSettings.map { $0 != settings } ?? false
        let errorChanged = newError?.localizedDescription != error?.localizedDescription
        if let newSettings, settingsChanged {
            settings = newSettings
        }
        if errorChanged {
            error = newError
        }
        if settingsChanged || errorChanged {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        }
    }

    /// Saves a preset named `name` at `width` × `height` into the file, replacing one with the same name, and
    /// returns it. Reads the whole file first, so a hand edit made since isn't lost; throws without writing anything
    /// when the file can't be read or written, or has a value the app can't use.
    @discardableResult
    func save(name: String, width: Int, height: Int) throws -> ViewportPreset {
        let existing = try contents()
        let saved = try SettingsFile.savingViewportPreset(name: name, width: width, height: height, in: existing)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try saved.data.write(to: url, options: .atomic)
        lastContents = saved.data
        update(settings: saved.settings, error: nil)
        return saved.preset
    }

    /// Creates the folder and a file holding `{}` when there is no file yet, for Settings… to open. Never touches a
    /// file that exists.
    func createFileIfMissing() throws {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{}\n".utf8).write(to: url, options: .withoutOverwriting)
        reload()
    }

    /// The file's contents, or nil when there is no file.
    private func contents() throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    // MARK: Watching

    /// Starts watching the folder, which an editor's atomic replace changes, and the file, which a save in place
    /// changes. Creates the folder if it is missing, so there is something to watch.
    func startWatching() {
        guard folderSource == nil else { return }
        let folder = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        folderSource = source(for: folder, events: [.write, .rename, .delete])
        watchFile()
        reload()
    }

    func stopWatching() {
        pendingRead?.cancel()
        pendingRead = nil
        folderSource?.cancel()
        folderSource = nil
        fileSource?.cancel()
        fileSource = nil
    }

    /// Watches the file now at `url`. A replaced file is a new file, so this runs again after every change.
    private func watchFile() {
        fileSource?.cancel()
        fileSource = source(for: url, events: [.write, .extend, .delete, .rename, .attrib])
    }

    private func source(
        for url: URL, events: DispatchSource.FileSystemEvent
    ) -> DispatchSourceFileSystemObject? {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: events, queue: .main)
        source.setEventHandler { [weak self] in
            self?.scheduleRead()
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        return source
    }

    /// Reads the file once its writes have settled.
    private func scheduleRead() {
        pendingRead?.cancel()
        let read = DispatchWorkItem { [weak self] in
            guard let self, self.folderSource != nil else { return }
            self.pendingRead = nil
            self.watchFile()
            self.reload()
        }
        pendingRead = read
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay, execute: read)
    }
}
