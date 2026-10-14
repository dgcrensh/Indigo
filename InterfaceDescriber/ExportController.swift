import AppKit
import DescriberCore
import UniformTypeIdentifiers

/// File > Export (spec Section 11): the Markdown outline, the single-file JSON, and a PNG of each screen. Exports read
/// the project as it is, including a region being typed in the details panel, and change nothing in it.
@MainActor
final class ExportController {
    let model: DocumentModel
    /// The window the panels and alerts show on.
    weak var window: NSWindow?
    /// The document, for the name exports take and the folder the panels start in.
    weak var document: NSDocument?
    /// The scale PNG Images… used last, which it offers again.
    private(set) var pngScale = 2

    init(model: DocumentModel) {
        self.model = model
    }

    /// The document's name without its extension, such as `Acme` for `Acme.uidesc`: the Markdown's title and the
    /// exports' default file name.
    var documentName: String {
        if let url = document?.fileURL {
            return url.deletingPathExtension().lastPathComponent
        }
        return document?.displayName ?? model.project.name
    }

    /// The folder the document's package is in, or nil for a document never saved.
    private var directory: URL? {
        document?.fileURL?.deletingLastPathComponent()
    }

    // MARK: Writing

    func writeMarkdown(to url: URL) throws {
        try MarkdownExport.data(for: model.project, title: documentName).write(to: url, options: .atomic)
    }

    func writeJSON(to url: URL) throws {
        try ProjectJSONExport.data(for: model.project).write(to: url, options: .atomic)
    }

    /// Writes one PNG per screen into `folder`, replacing files of the same names, and returns their URLs in sidebar
    /// order.
    @discardableResult
    func writePNGs(to folder: URL, scale: Int) throws -> [URL] {
        let project = model.project
        let names = ScreenImage.fileNames(for: project, scale: scale)
        var urls: [URL] = []
        for screen in project.screens {
            guard let name = names[screen.id] else { continue }
            guard let data = ScreenImageRenderer.pngData(for: screen, in: project, scale: scale) else {
                throw ExportError.imageFailed(screen: screen.name)
            }
            let url = folder.appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            urls.append(url)
        }
        return urls
    }

    // MARK: Panels

    func exportMarkdown() {
        let type = UTType("net.daringfireball.markdown") ?? UTType(filenameExtension: "md") ?? .plainText
        runSavePanel(type: type, fileName: "\(documentName).md", write: writeMarkdown(to:))
    }

    func exportJSON() {
        runSavePanel(type: .json, fileName: "\(documentName).json", write: writeJSON(to:))
    }

    /// Asks for a folder and a scale, then writes every screen's PNG there.
    func exportPNGs() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Export"
        panel.message = "Choose a folder for one PNG per screen. Files with the same names are replaced."
        panel.directoryURL = directory
        let scalePopUp = NSPopUpButton()
        for scale in ScreenImage.scales {
            scalePopUp.addItem(withTitle: "\(scale)×")
            scalePopUp.lastItem?.tag = scale
        }
        scalePopUp.selectItem(withTag: pngScale)
        let label = NSTextField(labelWithString: "Scale:")
        let accessory = NSStackView(views: [label, scalePopUp])
        accessory.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        panel.accessoryView = accessory
        panel.isAccessoryViewDisclosed = true
        begin(panel) { [weak self] in
            guard let self, let folder = panel.url else { return }
            let scale = scalePopUp.selectedTag()
            self.pngScale = scale
            try self.writePNGs(to: folder, scale: scale)
        }
    }

    private func runSavePanel(type: UTType, fileName: String, write: @escaping (URL) throws -> Void) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = fileName
        panel.directoryURL = directory
        panel.canCreateDirectories = true
        begin(panel) {
            guard let url = panel.url else { return }
            try write(url)
        }
    }

    /// Shows `panel` as a sheet on the window (or on its own without one) and runs `export` when the user confirms,
    /// showing any error it throws.
    private func begin(_ panel: NSSavePanel, export: @escaping () throws -> Void) {
        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK else { return }
            do {
                try export()
            } catch {
                self?.show(error)
            }
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            panel.begin(completionHandler: finish)
        }
    }

    private func show(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = "The export couldn't be written."
        alert.informativeText = error.localizedDescription
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}

enum ExportError: LocalizedError {
    case imageFailed(screen: String)

    var errorDescription: String? {
        switch self {
        case .imageFailed(let screen): "The image of “\(screen)” couldn't be drawn."
        }
    }
}
