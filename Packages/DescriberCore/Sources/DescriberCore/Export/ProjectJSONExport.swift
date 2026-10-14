import Foundation

/// The single-file JSON export (spec Section 11): the manifest with every screen inline, for tools and chat apps that
/// can't read a package folder. Each screen is written exactly as its screen file is; editor state is left out.
public enum ProjectJSONExport {
    /// Keys in the order `schemaVersion, name, units, screens, variantGroups`, with no `variantGroups` when there are
    /// none.
    public static func json(for project: Project) -> JSONValue {
        var pairs: [(key: String, value: JSONValue)] = [
            ("schemaVersion", .int(Project.schemaVersion)),
            ("name", .string(project.name)),
            ("units", .string(Project.units)),
            ("screens", .array(project.screens.map { ProjectEncoding.screen($0, in: project) })),
        ]
        if case .object(let manifest) = ProjectEncoding.manifest(project, files: [:]),
            let groups = manifest.first(where: { $0.key == "variantGroups" })
        {
            pairs.append(groups)
        }
        return .object(pairs)
    }

    /// The file, in the package's formatting.
    public static func data(for project: Project) -> Data {
        OrderedJSONWriter.data(json(for: project))
    }
}
