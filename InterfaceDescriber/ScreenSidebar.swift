import DescriberCore
import SwiftUI

/// The screens of the project in sidebar order, with a header above each variant group (spec 8.1 and 8.3), each
/// drawn as a Paper card with a thumbnail of its regions. Clicking a card shows its screen; dragging reorders; the
/// context menu renames, duplicates, groups and deletes; a dashed card at the end adds a screen. Under the list, a
/// card with the active screen's kind, viewport and scrolling (spec 8.2 and 3.4). Every change goes through the
/// screen controller as a command.
struct ScreenSidebar: View {
    @Bindable var model: DocumentModel
    let controller: ScreenController
    @State private var renaming: ScreenID?
    @State private var draftName = ""
    @FocusState private var nameFieldFocused: Bool

    // The body reads the project, its screens and the settings through Observation, so it redraws when what it shows
    // changes, not after every edit. Region edits reach a card only through its thumbnail revision.
    var body: some View {
        let outline = SidebarOutline(project: model.project)
        VStack(spacing: 0) {
            // No list selection: the active card draws its own accent ring instead of the system highlight.
            List {
                ForEach(outline.rows, id: \.self) { row in
                    switch row {
                    case .group(let index):
                        groupHeader(outline.groups[index])
                            .paperListRow(leading: 12)
                    case .screen(let id, let group):
                        if let screen = model.project.screen(withID: id) {
                            screenCard(screen)
                                .paperListRow(leading: group != nil ? 20 : 10)
                        }
                    }
                }
                .onMove { rows, destination in
                    controller.moveRows(Array(rows), to: destination)
                }
                newScreenCard
                    .paperListRow(leading: 10)
                    .moveDisabled(true)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            if let screen = model.activeScreen {
                ScreenSettingsView(screen: screen, controller: controller)
                    .paperCard()
                    .padding(10)
            }
        }
        .background(Color(nsColor: .paper { $0.chrome }))
    }

    private func groupHeader(_ group: VariantGroup) -> some View {
        Label(group.name, systemImage: "square.stack")
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundStyle(Color(nsColor: .paper { $0.secondaryInk }))
            .moveDisabled(true)
            .contextMenu {
                if let member = group.screens.first {
                    Button("Rename Group…") { controller.promptRenameVariantGroup(containing: member) }
                    Button("Ungroup Variants") { controller.ungroupVariants(containing: member) }
                }
            }
    }

    /// A screen's card: its thumbnail, its name, and its viewport, with an accent ring while it is showing.
    private func screenCard(_ screen: Screen) -> some View {
        let isActive = model.activeScreenID == screen.id
        return HStack(spacing: 10) {
            ScreenThumbnailView(screen: screen, revision: model.thumbnailRevision(for: screen.id))
            VStack(alignment: .leading, spacing: 2) {
                if renaming == screen.id {
                    TextField("Name", text: $draftName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .focused($nameFieldFocused)
                        .onSubmit { commitRename() }
                        .onExitCommand { renaming = nil }
                        .onAppear { nameFieldFocused = true }
                        .onChange(of: nameFieldFocused) { _, focused in
                            if !focused { commitRename() }
                        }
                } else {
                    Text(screen.name)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(nsColor: .paper { $0.ink }))
                        .lineLimit(1)
                }
                Text(screen.sidebarDetail(userPresets: controller.presets.user))
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Color(nsColor: .paper { $0.secondaryInk }))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .paperCard(selected: isActive)
        .contentShape(Rectangle())
        .onTapGesture { model.show(screen.id) }
        .contextMenu { screenMenu(screen) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }

    /// The dashed card under the last screen, which adds one.
    private var newScreenCard: some View {
        Button {
            controller.newScreen()
        } label: {
            Label("New Screen", systemImage: "plus")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Color(nsColor: .paper { $0.secondaryInk }))
                .frame(maxWidth: .infinity, minHeight: 36)
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            Color(nsColor: .paper { $0.sheetBorder }), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func screenMenu(_ screen: Screen) -> some View {
        let id = screen.id
        Button("Rename") {
            draftName = screen.name
            renaming = id
        }
        Button("Duplicate") { controller.duplicateScreen(id) }
        Menu("New Variant") {
            ViewportChoices(controller: controller) { controller.newVariant(of: id, viewport: $0) }
        }
        Menu("Make Variant Of") {
            ForEach(model.project.screens.filter { $0.id != id }, id: \.id) { other in
                Button(other.name) { controller.makeVariant(id, of: other.id) }
            }
        }
        if controller.isInVariantGroup(id) {
            Button("Remove from Variant Group") { controller.removeFromVariantGroup(id) }
        }
        Divider()
        Button("Delete…") { controller.deleteScreen(id) }
            .disabled(!controller.canDelete(id))
    }

    private func commitRename() {
        guard let id = renaming else { return }
        renaming = nil
        controller.renameScreen(id, to: draftName)
    }

    /// The sidebar icon for each screen kind.
    static func symbol(for kind: ScreenKind) -> String {
        switch kind {
        case .screen: "rectangle"
        case .modal: "rectangle.center.inset.filled"
        case .sheet: "rectangle.bottomhalf.inset.filled"
        case .popover: "bubble.middle.top"
        case .menu: "filemenu.and.selection"
        case .alert: "exclamationmark.triangle"
        }
    }
}

extension View {
    /// A list row with no background or separator, inset so the cards sit 8 pt apart.
    func paperListRow(leading: CGFloat) -> some View {
        listRowInsets(EdgeInsets(top: 4, leading: leading, bottom: 4, trailing: 10))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    /// A Paper card: card color, 12 pt corners and the soft shadow, with a 2 pt accent ring when `selected`.
    func paperCard(selected: Bool = false) -> some View {
        background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .paper { $0.card }))
                .shadow(color: Color(nsColor: .paper { $0.sheetShadow }), radius: 5, y: 2)
        }
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color(nsColor: .paper { $0.accent }), lineWidth: 2)
            }
        }
    }

    /// A text field on a Paper well.
    func paperWell() -> some View {
        textFieldStyle(.plain)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .paper { $0.well })))
    }
}

/// The viewport presets as menu buttons: the built-in ones, the user's, and This Device.
struct ViewportChoices: View {
    let controller: ScreenController
    let choose: (Viewport) -> Void

    var body: some View {
        let presets = controller.presets
        ForEach(presets.builtIn, id: \.id) { preset in
            Button(ViewportPresets.menuTitle(for: preset)) { choose(preset.viewport) }
        }
        if !presets.user.isEmpty {
            Divider()
            ForEach(presets.user, id: \.id) { preset in
                Button(ViewportPresets.menuTitle(for: preset)) { choose(preset.viewport) }
            }
        }
        Divider()
        Button("This Device") {
            if let viewport = controller.thisDeviceViewport { choose(viewport) }
        }
    }
}

/// The active screen's kind, viewport and scrolling, under the screen list.
struct ScreenSettingsView: View {
    let screen: Screen
    let controller: ScreenController

    var body: some View {
        let id = screen.id
        let viewport = screen.viewport
        VStack(alignment: .leading, spacing: 8) {
            Picker(
                "Kind",
                selection: Binding(get: { screen.kind }, set: { controller.setKind($0, of: id) })
            ) {
                ForEach(ScreenKind.allCases, id: \.self) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            Menu {
                ViewportChoices(controller: controller) { controller.setViewport($0, of: id) }
                Button("Custom Size…") { controller.chooseCustomSize(for: id) }
                Divider()
                Button("Refresh to Current Display") { controller.refreshThisDevice(for: id) }
                    .disabled(viewport.preset != ViewportPresets.thisDeviceID)
                Button("Save Viewport as Preset…") { controller.saveViewportAsPreset(for: id) }
            } label: {
                Text(ViewportPresets.label(for: viewport, userPresets: controller.presets.user))
            }
            HStack(spacing: 4) {
                TextField(
                    "Width",
                    value: Binding(
                        get: { screen.viewport.width },
                        set: { controller.setSize(width: $0, height: screen.viewport.height, of: id) }),
                    format: .number.grouping(.never)
                )
                .paperWell()
                Text("×")
                TextField(
                    "Height",
                    value: Binding(
                        get: { screen.viewport.height },
                        set: { controller.setSize(width: screen.viewport.width, height: $0, of: id) }),
                    format: .number.grouping(.never)
                )
                .paperWell()
                Text("pt")
                    .foregroundStyle(.secondary)
            }
            Toggle(
                "Scrolls",
                isOn: Binding(get: { screen.scroll != nil }, set: { controller.setScrolls($0, of: id) }))
            if let scroll = screen.scroll {
                Picker(
                    "Axis",
                    selection: Binding(get: { scroll.axis }, set: { controller.setScroll(axis: $0, of: id) })
                ) {
                    ForEach(ScrollAxis.allCases, id: \.self) { axis in
                        Text(axis.displayName).tag(axis)
                    }
                }
                HStack(spacing: 4) {
                    TextField(
                        "Content width",
                        value: Binding(
                            get: { scroll.contentWidth }, set: { controller.setScroll(width: $0, of: id) }),
                        format: .number.grouping(.never)
                    )
                    .paperWell()
                    Text("×")
                    TextField(
                        "Content height",
                        value: Binding(
                            get: { scroll.contentHeight }, set: { controller.setScroll(height: $0, of: id) }),
                        format: .number.grouping(.never)
                    )
                    .paperWell()
                    Text("pt")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .controlSize(.small)
        .padding(10)
    }
}
