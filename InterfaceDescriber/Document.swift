import AppKit

/// A `.uidesc` project package. Reading and writing arrive in milestone 3; here the document only opens an
/// empty window.
final class Document: NSDocument {
    override class var autosavesInPlace: Bool {
        false
    }

    override func makeWindowControllers() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSView()
        window.center()
        addWindowController(NSWindowController(window: window))
    }

    override func read(from fileWrapper: FileWrapper, ofType typeName: String) throws {
    }

    override func fileWrapper(ofType typeName: String) throws -> FileWrapper {
        FileWrapper(directoryWithFileWrappers: [:])
    }
}
