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
    /// away and which are unchanged.
    public static func write(project: Project, previous: PackageTree = [:]) -> WriteResult {
        let files = screenFiles(for: project)
        var tree: PackageTree = [:]
        tree[manifestPath] = OrderedJSONWriter.data(ProjectEncoding.manifest(project, files: files))
        for screen in project.screens {
            tree[files[screen.id]!] = OrderedJSONWriter.data(ProjectEncoding.screen(screen, in: project))
        }
        if !project.editorState.isEmpty {
            tree[editorStatePath] = OrderedJSONWriter.data(ProjectEncoding.editorState(project.editorState))
        }

        var previouslyOwned = Set(previousScreenFiles(previous))
        if previous[editorStatePath] != nil {
            previouslyOwned.insert(editorStatePath)
        }
        let removed = previouslyOwned.subtracting(tree.keys)
        let unchanged = Set(tree.compactMap { path, data in previous[path] == data ? path : nil })
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
