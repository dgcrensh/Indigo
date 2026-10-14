import Foundation

/// A package's files in memory, keyed by path relative to the package root (for example `screens/login.json`).
/// The app converts this to and from `FileWrapper`; the core never touches the file system.
public typealias PackageTree = [String: Data]

/// Converts between the model and a package tree.
public enum ProjectPackage {
    public static let manifestPath = "project.json"
    public static let screensDirectory = "screens"
    public static let editorStatePath = ".editor-state.json"

    /// What writing a project produced, relative to the package as it was before.
    public struct WriteResult: Equatable {
        /// Every file the project consists of now. Unknown files in the previous package are not included.
        public var tree: PackageTree
        /// Files from the previous package that no longer belong to the project: screen files of renamed or
        /// deleted screens, and editor state that has gone back to defaults.
        public var removed: Set<String>
        /// Paths in `tree` whose contents are identical to the previous package, so they need not be rewritten.
        public var unchanged: Set<String>

        /// Paths in `tree` that are new or different from the previous package.
        public var changed: Set<String> {
            Set(tree.keys).subtracting(unchanged)
        }

        /// The edits that bring the previous package up to date with this write.
        public var changes: Changes {
            Changes(written: tree.filter { !unchanged.contains($0.key) }, deleted: removed)
        }
    }

    /// Edits to a package: files to write and files to delete. Files not named are left alone.
    public struct Changes: Equatable {
        /// New or different files, keyed by relative path.
        public var written: PackageTree
        /// Relative paths of files to remove.
        public var deleted: Set<String>

        public init(written: PackageTree = [:], deleted: Set<String> = []) {
            self.written = written
            self.deleted = deleted
        }

        public var isEmpty: Bool {
            written.isEmpty && deleted.isEmpty
        }
    }

    /// `tree` with `changes` applied. Files the project doesn't own, such as a `references/` folder, are kept.
    public static func applying(_ changes: Changes, to tree: PackageTree) -> PackageTree {
        var result = tree
        for path in changes.deleted {
            result[path] = nil
        }
        result.merge(changes.written) { _, new in new }
        return result
    }

    /// Reads a project from a tree.
    public static func read(_ tree: PackageTree) throws -> Project {
        try read { tree[$0] }
    }

    /// Reads a project, asking `readFile` for each relative path it needs. `project.json` is read first, and
    /// nothing else is read if its `schemaVersion` isn't supported.
    public static func read(reading readFile: (String) -> Data?) throws -> Project {
        try ProjectDecoding.project(reading: readFile)
    }

    /// The path of each screen's file, from slugs of the screen names in sidebar order.
    public static func screenFiles(for project: Project) -> [ScreenID: String] {
        let slugs = Slug.unique(project.screens.map(\.name))
        var files: [ScreenID: String] = [:]
        for (screen, slug) in zip(project.screens, slugs) {
            files[screen.id] = "\(screensDirectory)/\(slug).json"
        }
        return files
    }

    /// Writes a project. Pass the package as it was last read or written as `previous` to learn which files moved
    /// away and which are unchanged. Pass the same `cache` to every write of a document to skip writing the text of
    /// files whose content hasn't changed since the last write; the result is the same with or without it.
    public static func write(
        project: Project, previous: PackageTree = [:], cache: PackageEncodingCache? = nil
    ) -> WriteResult {
        let files = screenFiles(for: project)
        var values: [(path: String, value: JSONValue)] = [
            (manifestPath, ProjectEncoding.manifest(project, files: files))
        ]
        for screen in project.screens {
            values.append((files[screen.id]!, ProjectEncoding.screen(screen, in: project)))
        }
        if !project.editorState.isEmpty {
            values.append((editorStatePath, ProjectEncoding.editorState(project.editorState)))
        }

        var tree: PackageTree = [:]
        var unchanged: Set<String> = []
        for (path, value) in values {
            if let cached = cache?.entries[path], let old = previous[path], cached.value.isIdentical(to: value),
                old == cached.data
            {
                tree[path] = old
                unchanged.insert(path)
                continue
            }
            let data = OrderedJSONWriter.data(value)
            cache?.entries[path] = (value, data)
            tree[path] = data
            if previous[path] == data {
                unchanged.insert(path)
            }
        }
        cache?.entries = cache?.entries.filter { tree[$0.key] != nil } ?? [:]

        var previouslyOwned = Set(previousScreenFiles(previous))
        if previous[editorStatePath] != nil {
            previouslyOwned.insert(editorStatePath)
        }
        let removed = previouslyOwned.subtracting(tree.keys)
        return WriteResult(tree: tree, removed: removed, unchanged: unchanged)
    }

    /// Screen files the previous manifest listed. Unreadable manifests list nothing, so nothing is removed.
    private static func previousScreenFiles(_ previous: PackageTree) -> [String] {
        struct Manifest: Decodable {
            struct Entry: Decodable { var file: String }
            var screens: [Entry]
        }
        guard let data = previous[manifestPath],
            let manifest = try? JSONDecoder().decode(Manifest.self, from: data)
        else { return [] }
        return manifest.screens.map(\.file).filter { previous[$0] != nil }
    }
}

/// What a document last wrote for each file: the value and its text. Values are compared exactly (strings by their
/// UTF-8 bytes), so a file whose value is identical can reuse its text without writing it again. Keep one per
/// document and replace it whenever the document's package is replaced, as when reading or reverting.
public final class PackageEncodingCache {
    var entries: [String: (value: JSONValue, data: Data)] = [:]

    public init() {}
}
