import DescriberCore
import Foundation

/// Converts between the core's `PackageTree` (relative paths to file contents) and the `FileWrapper` tree
/// `NSDocument` reads and writes.
enum PackageWrapper {
    /// Every regular file under `wrapper`, keyed by path relative to it.
    static func tree(of wrapper: FileWrapper) -> PackageTree {
        var tree: PackageTree = [:]
        collect(wrapper, prefix: "", into: &tree)
        return tree
    }

    /// The contents of the regular file at `path` relative to `root`, reading no other file.
    static func contents(at path: String, in root: FileWrapper) -> Data? {
        var wrapper = root
        for component in path.split(separator: "/") {
            guard let child = wrapper.fileWrappers?[String(component)] else { return nil }
            wrapper = child
        }
        return wrapper.isRegularFile ? wrapper.regularFileContents : nil
    }

    /// Applies `changes` to the directory wrapper `root` in place. Files the changes don't name keep their
    /// wrappers, so a save can copy them instead of writing them again.
    static func apply(_ changes: ProjectPackage.Changes, to root: FileWrapper) {
        for path in changes.deleted {
            let (directories, name) = split(path)
            if let directory = directory(at: directories, in: root, creating: false),
                let file = directory.fileWrappers?[name]
            {
                directory.removeFileWrapper(file)
            }
        }
        for (path, data) in changes.written {
            let (directories, name) = split(path)
            guard let directory = directory(at: directories, in: root, creating: true) else { continue }
            if let existing = directory.fileWrappers?[name] {
                directory.removeFileWrapper(existing)
            }
            let file = FileWrapper(regularFileWithContents: data)
            file.preferredFilename = name
            directory.addFileWrapper(file)
        }
    }

    private static func collect(_ wrapper: FileWrapper, prefix: String, into tree: inout PackageTree) {
        for (name, child) in wrapper.fileWrappers ?? [:] {
            let path = prefix.isEmpty ? name : "\(prefix)/\(name)"
            if child.isDirectory {
                collect(child, prefix: path, into: &tree)
            } else if child.isRegularFile, let data = child.regularFileContents {
                tree[path] = data
            }
        }
    }

    private static func split(_ path: String) -> (directories: [String], name: String) {
        var components = path.split(separator: "/").map(String.init)
        let name = components.removeLast()
        return (components, name)
    }

    /// The directory wrapper at `components` under `root`, creating missing directories when asked. Nil when a
    /// component is missing and `creating` is false, or names something that isn't a directory.
    private static func directory(at components: [String], in root: FileWrapper, creating: Bool) -> FileWrapper? {
        var directory = root
        for component in components {
            if let child = directory.fileWrappers?[component] {
                guard child.isDirectory else { return nil }
                directory = child
            } else if creating {
                let child = FileWrapper(directoryWithFileWrappers: [:])
                child.preferredFilename = component
                directory.addFileWrapper(child)
                directory = child
            } else {
                return nil
            }
        }
        return directory
    }
}
