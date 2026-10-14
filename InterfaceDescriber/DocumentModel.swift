import DescriberCore
import Foundation
import Observation

/// What a document window shows: the edit session holding the project, and the active screen. Views read it
/// through Observation, so they follow undo, redo and Revert.
@Observable
final class DocumentModel {
    /// Replaced when the document is read or reverted.
    var session: EditSession
    /// The screen the canvas shows. `show(_:)` changes it as the user does and saves it as the last active screen.
    var activeScreenID: ScreenID?
    /// Link-following history for Back and Forward (spec 8.4). Window state, not saved or undone.
    var history = NavigationHistory()
    /// The sidebar order as of the last change, to find the screen that takes the place of a removed active one.
    @ObservationIgnored private var screenOrder: [ScreenID] = []
    /// Changes after every command, undo, redo and replacement of the project, so views that draw the model (the
    /// canvas) know to draw again. Regions aren't observable themselves.
    private(set) var revision = 0
    /// Whether drawing, moving and resizing snap to the grid, which the canvas then shows. Toggled with `S`; starts
    /// from the settings when the window opens.
    var snappingEnabled = true
    /// The active tool. Every window starts with the Select tool.
    var tool: Tool = .select
    /// The selected regions on the active screen. Editor state, so changing it isn't an edit.
    var selection: [RegionID] = []
    /// The app settings in use: the window controller copies them in from the settings store when they change.
    var settings = AppSettings.defaults {
        didSet { keybinds = settings.keybinds }
    }
    /// The keybinds, the defaults with any overrides from settings on top.
    private(set) var keybinds = KeybindRegistry.defaults

    init(project: Project) {
        session = EditSession(project: project)
        activeScreenID = project.initialScreen
        screenOrder = SidebarOutline(project: project).screens
        recordThumbnailFingerprints()
    }

    var project: Project {
        session.project
    }

    var activeScreen: Screen? {
        activeScreenID.flatMap { project.screen(withID: $0) }
    }

    /// Each screen's thumbnail revision, which each sidebar card reads on its own so only the edited screen's redraws.
    @ObservationIgnored private var thumbnailRevisions: [ScreenID: ThumbnailRevision] = [:]
    /// What each screen's thumbnail last drew, to tell which screens an edit changed.
    @ObservationIgnored private var thumbnailFingerprints: [ScreenID: Int] = [:]
    @ObservationIgnored private var thumbnailTimer: Timer?
    /// The least time between two redraws of a screen's thumbnail.
    static let thumbnailThrottle: TimeInterval = 0.3

    /// The region open in the details panel, or nil while the panel is closed.
    private(set) var details: RegionEditor?
    /// Called after the details panel records an undo step, with its name, so the document can register it with
    /// the undo manager.
    @ObservationIgnored var didRecordStep: ((String) -> Void)?
    /// Called after the details panel opens, switches to another region, or closes, so the window can show it.
    @ObservationIgnored var detailsDidChange: (() -> Void)?

    /// Starts over with `project`, as after reading or reverting.
    func replaceProject(with project: Project) {
        let hadDetails = details != nil
        details = nil
        session = EditSession(project: project)
        activeScreenID = project.initialScreen
        history = NavigationHistory()
        screenOrder = SidebarOutline(project: project).screens
        // Every card draws the new project now, so the next check only picks up edits made after this.
        thumbnailFingerprints = [:]
        recordThumbnailFingerprints()
        for revision in thumbnailRevisions.values {
            revision.value += 1
        }
        noteChange()
        if hadDetails {
            detailsDidChange?()
        }
    }

    // MARK: Details panel

    /// Opens an existing region in the details panel and selects it, committing the region open there now.
    func openDetails(for region: RegionID) throws {
        guard details?.region != region else { return }
        try openDetails { try RegionEditor(region: region, in: session) }
    }

    /// Draws a region with `command` and opens it in the details panel, committing the region open there now. The
    /// drawing is recorded with the panel session when it closes, or dropped with a blank title.
    func openDetails(creating command: CreateRegion) throws {
        try openDetails { try RegionEditor(creating: command, in: session) }
    }

    private func openDetails(_ makeEditor: () throws -> RegionEditor) throws {
        commitDetails()
        details = nil
        do {
            let editor = try makeEditor()
            details = editor
            selection = [editor.region]
        } catch {
            noteChange()
            detailsDidChange?()
            throw error
        }
        noteChange()
        detailsDidChange?()
    }

    /// Changes a field of the region open in the details panel.
    func editDetails(_ change: (RegionEditor) throws -> Void) rethrows {
        guard let details else { return }
        try change(details)
        noteChange()
    }

    /// Commits the region open in the details panel as one undo step and closes the panel.
    func closeDetails() {
        guard details != nil else { return }
        commitDetails()
        details = nil
        detailsDidChange?()
    }

    /// Puts back everything the open details session changed, records nothing, and closes the panel. Undo and redo
    /// do this first, so they never interleave with unrecorded changes.
    func cancelDetails() {
        guard let details else { return }
        details.cancel()
        self.details = nil
        noteChange()
        detailsDidChange?()
    }

    private func commitDetails() {
        guard let details else { return }
        if case .recorded(let actionName) = details.commit() {
            didRecordStep?(actionName)
        }
        noteChange()
    }

    /// Shows `screen` on the canvas and saves it as the last active screen in the editor state, which the next save
    /// writes (spec 3.1). Like zoom, it isn't an edit.
    func show(_ screen: ScreenID) {
        guard project.screen(withID: screen) != nil else { return }
        if activeScreenID != screen {
            activeScreenID = screen
        }
        if project.editorState.lastActiveScreen != screen {
            project.editorState.lastActiveScreen = screen
        }
    }

    /// Records that the project changed. When the change removed the active screen, as undoing a new screen does,
    /// the screen that took its place in the sidebar is shown.
    func noteChange() {
        revision += 1
        if let active = activeScreenID, project.screen(withID: active) == nil {
            let replacement = ScreenNavigation.replacement(forRemoved: active, previousOrder: screenOrder, in: project)
            activeScreenID = nil
            if let replacement {
                show(replacement)
            }
        }
        screenOrder = SidebarOutline(project: project).screens
        scheduleThumbnailRefresh()
    }

    // MARK: Thumbnails

    /// The revision `screen`'s sidebar thumbnail draws from. It changes after an edit to that screen, at most once
    /// per `thumbnailThrottle`.
    func thumbnailRevision(for screen: ScreenID) -> ThumbnailRevision {
        if let revision = thumbnailRevisions[screen] {
            return revision
        }
        let revision = ThumbnailRevision()
        thumbnailRevisions[screen] = revision
        return revision
    }

    /// Checks the thumbnails once the throttle has passed, unless a check is already waiting.
    private func scheduleThumbnailRefresh() {
        guard thumbnailTimer == nil else { return }
        let timer = Timer(timeInterval: Self.thumbnailThrottle, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.thumbnailTimer = nil
                self?.refreshThumbnails()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        thumbnailTimer = timer
    }

    /// Bumps the thumbnail revision of each screen whose thumbnail would draw differently now.
    func refreshThumbnails() {
        for screen in project.screens {
            let fingerprint = ScreenThumbnail.fingerprint(of: screen)
            // A screen added since the last check counts as changed, in case it was edited since its card drew.
            if thumbnailFingerprints[screen.id] != fingerprint {
                thumbnailRevision(for: screen.id).value += 1
            }
            thumbnailFingerprints[screen.id] = fingerprint
        }
    }

    private func recordThumbnailFingerprints() {
        for screen in project.screens {
            thumbnailFingerprints[screen.id] = ScreenThumbnail.fingerprint(of: screen)
        }
    }
}

/// A screen's thumbnail revision, observed by its sidebar card alone.
@Observable
final class ThumbnailRevision {
    var value = 0
}
