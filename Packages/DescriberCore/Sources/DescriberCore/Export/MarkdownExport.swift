import Foundation

/// The Markdown outline export (spec Section 11): one document for the whole project, with a section per screen and
/// its regions as a nested list. Links between screens are anchors to the target screen's section.
public enum MarkdownExport {
    /// The outline of `project`. `title` heads the document; nil uses the project's name.
    public static func markdown(for project: Project, title: String? = nil) -> String {
        let title = title ?? project.name
        // Anchors are handed out in document order, so the title's heading counts before the screens'.
        var anchors = MarkdownText.Anchors()
        _ = anchors.next(for: title)
        var screenAnchors: [ScreenID: String] = [:]
        for screen in project.screens {
            screenAnchors[screen.id] = anchors.next(for: screen.name)
        }
        let writer = Writer(project: project, anchors: screenAnchors)

        let count = project.screens.count
        var lines = [
            "# \(MarkdownText.escaped(title))",
            "",
            "\(count) \(count == 1 ? "screen" : "screens"). Positions and sizes are in points, measured from each "
                + "screen's top-left corner. Regions are listed back to front, with the regions inside them nested "
                + "under them; a region without a kind is open.",
        ]
        if !project.screens.isEmpty {
            lines.append("")
            lines += project.screens.map { "- \(writer.link(to: $0.id))" }
        }
        for screen in project.screens {
            lines.append("")
            lines += writer.section(for: screen)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func data(for project: Project, title: String? = nil) -> Data {
        Data(markdown(for: project, title: title).utf8)
    }

    private struct Writer {
        let project: Project
        let anchors: [ScreenID: String]

        /// A link to a screen's section, or a note naming the ID of a screen that isn't in the project.
        func link(to id: ScreenID) -> String {
            guard let screen = project.screen(withID: id), let anchor = anchors[id] else {
                return "a missing screen (`\(id.rawValue)`)"
            }
            return "[\(MarkdownText.escaped(screen.name))](#\(anchor))"
        }

        func section(for screen: Screen) -> [String] {
            var lines = [
                "## \(MarkdownText.escaped(screen.name))",
                "",
                "- Kind: \(screen.kind.rawValue)",
                "- Viewport: \(viewport(screen.viewport))",
            ]
            if let scroll = screen.scroll {
                lines.append("- \(scrolling(scroll))")
            }
            for group in project.variantGroups where group.screens.contains(screen.id) {
                let others = group.screens.filter { $0 != screen.id }
                guard !others.isEmpty else { continue }
                lines.append(
                    "- Variants (\(MarkdownText.escaped(group.name))): "
                        + others.map(link(to:)).joined(separator: ", "))
            }
            lines.append("")
            if screen.regions.isEmpty {
                lines.append("No regions.")
            } else {
                lines.append("Regions:")
                lines.append("")
                for region in screen.regions {
                    lines += item(for: region, depth: 0)
                }
            }
            return lines
        }

        /// A region's list item, followed by its children's, nested one level deeper.
        private func item(for region: Region, depth: Int) -> [String] {
            let indent = String(repeating: "  ", count: depth)
            let continuation = indent + "  "
            let title = region.title.isEmpty ? "(untitled)" : MarkdownText.escaped(region.title)
            let kind = region.kind == .open ? "" : " (\(region.kind.rawValue))"
            let frame = region.frame
            var lines = ["\(indent)- **\(title)**\(kind): x \(frame.x), y \(frame.y), \(frame.w) × \(frame.h)."]
            let description = region.description.trimmingCharacters(in: .whitespacesAndNewlines)
            if !description.isEmpty {
                lines += description.components(separatedBy: .newlines).map {
                    $0.isEmpty ? "" : continuation + $0
                }
            }
            if let scroll = region.scroll {
                lines.append(continuation + scrolling(scroll) + ".")
            }
            if !region.links.isEmpty {
                let links = region.links.map { link -> String in
                    let target = self.link(to: link.screen)
                    guard let trigger = link.trigger, !trigger.isEmpty else { return target }
                    return "\(target) (\(MarkdownText.escaped(trigger)))"
                }
                lines.append(continuation + "Links to " + links.joined(separator: "; ") + ".")
            }
            for child in region.children {
                lines += item(for: child, depth: depth + 1)
            }
            return lines
        }

        /// Such as "iPhone 15, 393 × 852", "This Device, 1512 × 982", "Custom, 240 × 136", or a preset this build
        /// doesn't know (a user preset) by its ID.
        private func viewport(_ viewport: Viewport) -> String {
            let size = "\(viewport.width) × \(viewport.height)"
            guard let id = viewport.preset else { return "Custom, \(size)" }
            if id == ViewportPresets.thisDeviceID {
                return "This Device, \(size)"
            }
            let name = ViewportPresets.preset(withID: id)?.name ?? id
            return "\(MarkdownText.escaped(name)), \(size)"
        }

        /// Such as "Scrolls vertically, content 393 × 1200".
        private func scrolling(_ scroll: Scroll) -> String {
            let direction =
                switch scroll.axis {
                case .vertical: "vertically"
                case .horizontal: "horizontally"
                case .both: "in both directions"
                }
            return "Scrolls \(direction), content \(scroll.contentWidth) × \(scroll.contentHeight)"
        }
    }
}
