import Foundation

/// Reads a package's files into the model, validating as it goes. Derived fields (`name` and `file`'s name in the
/// manifest, `screenName` on links) are ignored; each screen file is the source of truth for its own name.
enum ProjectDecoding {
    /// Reads a project, asking `readFile` for each path it needs. `project.json` is read and its
    /// `schemaVersion` checked before any other file is requested.
    static func project(reading readFile: (String) -> Data?) throws -> Project {
        guard let manifestData = readFile(ProjectPackage.manifestPath) else {
            throw FormatError.missingManifest
        }
        let manifestFile = ProjectPackage.manifestPath
        let probe = try decode(VersionProbe.self, from: manifestData, file: manifestFile)
        guard probe.schemaVersion == Project.schemaVersion else {
            throw FormatError.unsupportedSchemaVersion(found: probe.schemaVersion)
        }
        let manifest = try decode(ManifestDTO.self, from: manifestData, file: manifestFile)

        var seenScreenIDs = Set<ScreenID>()
        var seenRegionIDs = Set<RegionID>()
        var screens: [Screen] = []
        var screenFiles: [ScreenID: String] = [:]
        for entry in manifest.screens {
            let expectedID = ScreenID(entry.id)
            guard seenScreenIDs.insert(expectedID).inserted else {
                throw FormatError.duplicateID(file: manifestFile, id: expectedID.rawValue)
            }
            guard let data = readFile(entry.file) else {
                throw FormatError.missingScreenFile(file: entry.file)
            }
            let dto = try decode(ScreenDTO.self, from: data, file: entry.file)
            let screen = try makeScreen(dto, file: entry.file, seenRegionIDs: &seenRegionIDs)
            guard screen.id == expectedID else {
                throw FormatError.screenIDMismatch(file: entry.file, expected: expectedID, found: screen.id)
            }
            screens.append(screen)
            screenFiles[screen.id] = entry.file
        }

        for screen in screens {
            for region in screen.allRegions {
                for link in region.links where !seenScreenIDs.contains(link.screen) {
                    throw FormatError.unknownLinkTarget(
                        file: screenFiles[screen.id] ?? "",
                        region: region.id,
                        target: link.screen
                    )
                }
            }
        }

        let groups = try (manifest.variantGroups ?? []).map { dto in
            let ids = dto.screens.map(ScreenID.init)
            if let unknown = ids.first(where: { !seenScreenIDs.contains($0) }) {
                throw FormatError.unknownVariantScreen(file: manifestFile, group: dto.name, screen: unknown)
            }
            return VariantGroup(name: dto.name, screens: ids)
        }

        let editorState = readFile(ProjectPackage.editorStatePath).flatMap(decodeEditorState) ?? EditorState()
        return Project(name: manifest.name, screens: screens, variantGroups: groups, editorState: editorState)
    }

    /// Editor state is best effort: anything unreadable gives nil, and the caller falls back to defaults.
    static func decodeEditorState(_ data: Data) -> EditorState? {
        guard let dto = try? JSONDecoder().decode(EditorStateDTO.self, from: data) else { return nil }
        var state = EditorState()
        state.lastActiveScreen = dto.lastActiveScreen.map(ScreenID.init)
        state.visibleDescriptions = Set((dto.visibleDescriptions ?? []).map(RegionID.init))
        for (key, screen) in dto.screens ?? [:] {
            var offsets: [RegionID: ScrollOffset] = [:]
            for (regionKey, offset) in screen.scrollOffsets ?? [:] {
                offsets[RegionID(regionKey)] = ScrollOffset(x: offset.x, y: offset.y)
            }
            state.screens[ScreenID(key)] = ScreenEditorState(
                zoom: screen.zoom ?? 1,
                panX: screen.panX ?? 0,
                panY: screen.panY ?? 0,
                gridSize: screen.gridSize,
                scrollOffsets: offsets
            )
        }
        return state
    }

    // MARK: Building the model

    private static func makeScreen(_ dto: ScreenDTO, file: String, seenRegionIDs: inout Set<RegionID>) throws
        -> Screen
    {
        guard let kind = ScreenKind(rawValue: dto.kind) else {
            throw FormatError.unknownKind(file: file, kind: dto.kind)
        }
        return Screen(
            id: ScreenID(dto.id),
            name: dto.name,
            kind: kind,
            viewport: Viewport(preset: dto.viewport.preset, width: dto.viewport.width, height: dto.viewport.height),
            scroll: try dto.scroll.map { try makeScroll($0, file: file) },
            regions: try (dto.regions ?? []).map { try makeRegion($0, file: file, seenRegionIDs: &seenRegionIDs) }
        )
    }

    private static func makeRegion(_ dto: RegionDTO, file: String, seenRegionIDs: inout Set<RegionID>) throws
        -> Region
    {
        let id = RegionID(dto.id)
        guard seenRegionIDs.insert(id).inserted else {
            throw FormatError.duplicateID(file: file, id: id.rawValue)
        }
        let kindName = dto.kind ?? RegionKind.open.rawValue
        guard let kind = RegionKind(rawValue: kindName) else {
            throw FormatError.unknownKind(file: file, kind: kindName)
        }
        return Region(
            id: id,
            title: dto.title,
            kind: kind,
            frame: Frame(x: dto.x, y: dto.y, w: dto.w, h: dto.h),
            description: dto.description ?? "",
            scroll: try dto.scroll.map { try makeScroll($0, file: file) },
            links: (dto.linksTo ?? []).map { Link(screen: ScreenID($0.screen), trigger: $0.trigger) },
            children: try (dto.children ?? []).map { try makeRegion($0, file: file, seenRegionIDs: &seenRegionIDs) }
        )
    }

    private static func makeScroll(_ dto: ScrollDTO, file: String) throws -> Scroll {
        guard let axis = ScrollAxis(rawValue: dto.axis) else {
            throw FormatError.unknownKind(file: file, kind: dto.axis)
        }
        return Scroll(axis: axis, contentWidth: dto.contentWidth, contentHeight: dto.contentHeight)
    }

    // MARK: JSON

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data, file: String) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch let error as DecodingError {
            throw FormatError.malformedJSON(file: file, detail: describe(error))
        } catch {
            throw FormatError.malformedJSON(file: file, detail: "\(error)")
        }
    }

    private static func describe(_ error: DecodingError) -> String {
        func path(_ codingPath: [CodingKey]) -> String {
            let parts = codingPath.map { key in key.intValue.map { "[\($0)]" } ?? ".\(key.stringValue)" }
            let joined = parts.joined()
            return joined.hasPrefix(".") ? String(joined.dropFirst()) : joined
        }
        switch error {
        case .keyNotFound(let key, let context):
            let location = path(context.codingPath)
            return "missing \"\(key.stringValue)\"" + (location.isEmpty ? "" : " in \(location)")
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            return "unexpected value at \(path(context.codingPath))"
        case .dataCorrupted(let context):
            return context.codingPath.isEmpty ? "not valid JSON" : "invalid value at \(path(context.codingPath))"
        @unknown default:
            return "\(error)"
        }
    }
}

// MARK: - File shapes

private struct VersionProbe: Decodable {
    var schemaVersion: Int?
}

private struct ManifestDTO: Decodable {
    struct Entry: Decodable {
        var id: String
        var file: String
    }

    struct Group: Decodable {
        var name: String
        var screens: [String]
    }

    var name: String
    var screens: [Entry]
    var variantGroups: [Group]?
}

private struct ScreenDTO: Decodable {
    struct ViewportDTO: Decodable {
        var preset: String?
        var width: Int
        var height: Int
    }

    var id: String
    var name: String
    var kind: String
    var viewport: ViewportDTO
    var scroll: ScrollDTO?
    var regions: [RegionDTO]?
}

private struct RegionDTO: Decodable {
    struct LinkDTO: Decodable {
        var screen: String
        var trigger: String?
    }

    var id: String
    var title: String
    var kind: String?
    var x: Int
    var y: Int
    var w: Int
    var h: Int
    var description: String?
    var scroll: ScrollDTO?
    var linksTo: [LinkDTO]?
    var children: [RegionDTO]?
}

private struct ScrollDTO: Decodable {
    var axis: String
    var contentWidth: Int
    var contentHeight: Int
}

private struct EditorStateDTO: Decodable {
    struct ScreenState: Decodable {
        struct Offset: Decodable {
            var x: Int
            var y: Int
        }

        var zoom: Double?
        var panX: Double?
        var panY: Double?
        var gridSize: Int?
        var scrollOffsets: [String: Offset]?
    }

    var lastActiveScreen: String?
    var screens: [String: ScreenState]?
    var visibleDescriptions: [String]?
}
