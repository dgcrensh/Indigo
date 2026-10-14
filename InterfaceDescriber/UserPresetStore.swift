import DescriberCore
import Foundation

/// The user's viewport presets, kept in `settings.json` in the app's Application Support folder (spec 8.2). Read when
/// the app starts and again before a preset is saved, so a hand edit made since isn't lost. Watching the file for
/// changes arrives with the rest of the settings in milestone 10.
final class UserPresetStore {
    static let shared = UserPresetStore(url: defaultURL)

    /// `~/Library/Application Support/Interface Describer/settings.json`.
    static var defaultURL: URL {
        let support =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent(AppIdentity.appName).appendingPathComponent(SettingsFile.fileName)
    }

    let url: URL
    private(set) var presets: [ViewportPreset] = []
    /// Why the file couldn't be read the last time, if it couldn't. The presets from before are kept.
    private(set) var readError: Error?

    init(url: URL) {
        self.url = url
        reload()
    }

    /// Reads the presets from the file again. A file that doesn't read leaves the presets as they were.
    func reload() {
        do {
            presets = try SettingsFile.viewportPresets(in: try contents())
            readError = nil
        } catch {
            readError = error
        }
    }

    /// Saves a preset named `name` at `width` × `height` into the file, replacing one with the same name, and
    /// returns it. Throws without writing anything when the file can't be read or written.
    @discardableResult
    func save(name: String, width: Int, height: Int) throws -> ViewportPreset {
        let existing = try contents()
        let current = try SettingsFile.viewportPresets(in: existing)
        let updated = ViewportPresets.saving(name: name, width: width, height: height, in: current)
        let data = try SettingsFile.replacingViewportPresets(updated, in: existing)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        presets = updated
        readError = nil
        return updated.first { $0.name.lowercased() == name.lowercased() } ?? updated[updated.count - 1]
    }

    /// The file's contents, or nil when there is no file yet.
    private func contents() throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }
}
