import Foundation

/// Builds the JSON for `project.json`, screen files and `.editor-state.json` in the spec's fixed key order
/// (spec 3.4), leaving out empty optional fields.
public enum ProjectEncoding {
    /// The manifest. `files` maps each screen to its path in the package; `name` and `file` are derived fields.
    public static func manifest(_ project: Project, files: [ScreenID: String]) -> JSONValue {
        var pairs: [(key: String, value: JSONValue)] = [
            ("schemaVersion", .int(Project.schemaVersion)),
            ("name", .string(project.name)),
            ("units", .string(Project.units)),
            (
                "screens",
                .array(
                    project.screens.map { screen in
                        .object([
                            ("id", .string(screen.id.rawValue)),
                            ("name", .string(screen.name)),
                            ("file", .string(files[screen.id] ?? "")),
                        ])
                    }
                )
            ),
        ]
        if !project.variantGroups.isEmpty {
            pairs.append(("variantGroups", .array(project.variantGroups.map(variantGroup))))
        }
        return .object(pairs)
    }

    /// One screen file. The project supplies the current names of link targets.
    public static func screen(_ screen: Screen, in project: Project) -> JSONValue {
        var pairs: [(key: String, value: JSONValue)] = [
            ("id", .string(screen.id.rawValue)),
            ("name", .string(screen.name)),
            ("kind", .string(screen.kind.rawValue)),
            ("viewport", viewport(screen.viewport)),
        ]
        if let scroll = screen.scroll {
            pairs.append(("scroll", self.scroll(scroll)))
        }
        pairs.append(("regions", .array(screen.regions.map { region($0, in: project) })))
        return .object(pairs)
    }

    /// One region and its subtree.
    public static func region(_ region: Region, in project: Project) -> JSONValue {
        var pairs: [(key: String, value: JSONValue)] = [
            ("id", .string(region.id.rawValue)),
            ("title", .string(region.title)),
        ]
        if region.kind != .open {
            pairs.append(("kind", .string(region.kind.rawValue)))
        }
        pairs += [
            ("x", .int(region.frame.x)),
            ("y", .int(region.frame.y)),
            ("w", .int(region.frame.w)),
            ("h", .int(region.frame.h)),
            ("description", .string(region.description)),
        ]
        if let scroll = region.scroll {
            pairs.append(("scroll", self.scroll(scroll)))
        }
        if !region.links.isEmpty {
            pairs.append(("linksTo", .array(region.links.map { link($0, in: project) })))
        }
        if !region.children.isEmpty {
            pairs.append(("children", .array(region.children.map { self.region($0, in: project) })))
        }
        return .object(pairs)
    }

    /// The editor-only state, with keys sorted so the file is stable.
    public static func editorState(_ state: EditorState) -> JSONValue {
        var pairs: [(key: String, value: JSONValue)] = []
        if let last = state.lastActiveScreen {
            pairs.append(("lastActiveScreen", .string(last.rawValue)))
        }
        pairs.append(
            (
                "screens",
                .object(
                    state.screens.keys.sorted().map { id in
                        (id.rawValue, screenEditorState(state.screens[id]!))
                    }
                )
            )
        )
        pairs.append(
            ("visibleDescriptions", .array(state.visibleDescriptions.sorted().map { .string($0.rawValue) }))
        )
        return .object(pairs)
    }

    private static func screenEditorState(_ state: ScreenEditorState) -> JSONValue {
        var pairs: [(key: String, value: JSONValue)] = [
            ("zoom", .double(state.zoom)),
            ("panX", .double(state.panX)),
            ("panY", .double(state.panY)),
        ]
        if let grid = state.gridSize {
            pairs.append(("gridSize", .int(grid)))
        }
        pairs.append(
            (
                "scrollOffsets",
                .object(
                    state.scrollOffsets.keys.sorted().map { id in
                        let offset = state.scrollOffsets[id]!
                        return (id.rawValue, .object([("x", .int(offset.x)), ("y", .int(offset.y))]))
                    }
                )
            )
        )
        return .object(pairs)
    }

    private static func viewport(_ viewport: Viewport) -> JSONValue {
        var pairs: [(key: String, value: JSONValue)] = []
        if let preset = viewport.preset {
            pairs.append(("preset", .string(preset)))
        }
        pairs += [("width", .int(viewport.width)), ("height", .int(viewport.height))]
        return .object(pairs)
    }

    private static func scroll(_ scroll: Scroll) -> JSONValue {
        .object([
            ("axis", .string(scroll.axis.rawValue)),
            ("contentWidth", .int(scroll.contentWidth)),
            ("contentHeight", .int(scroll.contentHeight)),
        ])
    }

    private static func link(_ link: Link, in project: Project) -> JSONValue {
        var pairs: [(key: String, value: JSONValue)] = [("screen", .string(link.screen.rawValue))]
        if let target = project.screen(withID: link.screen) {
            pairs.append(("screenName", .string(target.name)))
        }
        if let trigger = link.trigger, !trigger.isEmpty {
            pairs.append(("trigger", .string(trigger)))
        }
        return .object(pairs)
    }

    private static func variantGroup(_ group: VariantGroup) -> JSONValue {
        .object([
            ("name", .string(group.name)),
            ("screens", .array(group.screens.map { .string($0.rawValue) })),
        ])
    }
}
