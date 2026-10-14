import Foundation

/// Why a package could not be read. Every case names the file it is about, relative to the package root.
public enum FormatError: Error, Equatable, LocalizedError {
    /// The package has no `project.json`.
    case missingManifest
    /// `project.json` declares a `schemaVersion` this build doesn't read. Checked before anything else.
    case unsupportedSchemaVersion(found: Int?)
    /// A file isn't valid JSON or doesn't have the expected shape.
    case malformedJSON(file: String, detail: String)
    /// A manifest entry names a screen file that isn't in the package.
    case missingScreenFile(file: String)
    /// A screen file's `id` doesn't match its manifest entry.
    case screenIDMismatch(file: String, expected: ScreenID, found: ScreenID)
    /// A link targets a screen the project doesn't have.
    case unknownLinkTarget(file: String, region: RegionID, target: ScreenID)
    /// A variant group lists a screen the project doesn't have.
    case unknownVariantScreen(file: String, group: String, screen: ScreenID)
    /// Two screens or two regions share an ID.
    case duplicateID(file: String, id: String)
    /// A kind or scroll axis isn't one the format defines.
    case unknownKind(file: String, kind: String)

    public var file: String {
        switch self {
        case .missingManifest, .unsupportedSchemaVersion: return ProjectPackage.manifestPath
        case .malformedJSON(let file, _), .missingScreenFile(let file), .screenIDMismatch(let file, _, _),
            .unknownLinkTarget(let file, _, _), .unknownVariantScreen(let file, _, _), .duplicateID(let file, _),
            .unknownKind(let file, _):
            return file
        }
    }

    public var errorDescription: String? {
        switch self {
        case .missingManifest:
            return "The package has no \(ProjectPackage.manifestPath)."
        case .unsupportedSchemaVersion(let found):
            let version = found.map(String.init) ?? "none"
            return "\(file) has schemaVersion \(version), but this app reads only version \(Project.schemaVersion)."
        case .malformedJSON(let file, let detail):
            return "\(file) could not be read: \(detail)"
        case .missingScreenFile(let file):
            return "\(ProjectPackage.manifestPath) lists \(file), but the package has no such file."
        case .screenIDMismatch(let file, let expected, let found):
            return "\(file) has id \(found), but \(ProjectPackage.manifestPath) expects \(expected)."
        case .unknownLinkTarget(let file, let region, let target):
            return "\(file): region \(region) links to screen \(target), which isn't in the project."
        case .unknownVariantScreen(let file, let group, let screen):
            return "\(file): variant group \"\(group)\" lists screen \(screen), which isn't in the project."
        case .duplicateID(let file, let id):
            return "\(file): the id \(id) is used more than once."
        case .unknownKind(let file, let kind):
            return "\(file): \"\(kind)\" isn't a known kind."
        }
    }
}
