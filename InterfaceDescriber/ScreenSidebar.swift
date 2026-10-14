import DescriberCore
import SwiftUI

/// The screens of the project in sidebar order, with a header above each variant group (spec 8.1 and 8.3).
/// Selecting a screen shows it; dragging reorders; the context menu renames, duplicates, groups and deletes. Under
/// the list, the active screen's kind, viewport and scrolling (spec 8.2 and 3.4). Every change goes through the
/// screen controller as a command.
struct ScreenSidebar: View {
    @Bindable var model: DocumentModel
    let controller: ScreenController
    @State private var renaming: ScreenID?
    @State private var draftName = ""
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        let _ = model.revision
        let outline = SidebarOutline(project: model.project)
        VStack(spacing: 0) {
            List(selection: selection) {
                ForEach(outline.rows, id: \.self) { row in
                    switch row {
                    case .group(let index):
                        groupHeader(outline.groups[index])
                    case .screen(let id, let group):
                        if let screen = model.project.screen(withID: id) {
                            screenRow(screen, inGroup: group != nil)
                                .tag(Optional(id))
                        }
                    }
                }
                .onMove { rows, destination in
                    controller.moveRows(Array(rows), to: destination)
                }
            }
            .listStyle(.sidebar)
            if let screen = model.activeScreen {
                Divider()
                ScreenSettingsView(screen: screen, controller: controller)
            }
        }
    }

    /// Selecting a row shows its screen; clicking empty space keeps the screen showing.
    private var selection: Binding<ScreenID?> {
        Binding(
            get: { model.activeScreenID },
            set: { id in
                if let id { model.show(id) }
            })
    }

    private func groupHeader(_ group: VariantGroup) -> some View {
        Label(group.name, systemImage: "square.stack")
            .font(.caption)
            .foregroundStyle(.secondary)
            .moveDisabled(true)
            .contextMenu {
                if let member = group.screens.first {
                    Button("Rename Group…") { controller.promptRenameVariantGroup(containing: member) }
                    Button("Ungroup Variants") { controller.ungroupVariants(containing: member) }
                }
            }
    }

    @ViewBuilder
    private func screenRow(_ screen: Screen, inGroup: Bool) -> some View {
        Group {
            if renaming == screen.id {
                TextField("Name", text: $draftName)
                    .focused($nameFieldFocused)
                    .onSubmit { commitRename() }
                    .onExitCommand { renaming = nil }
                    .onAppear { nameFieldFocused = true }
                    .onChange(of: nameFieldFocused) { _, focused in
                        if !focused { commitRename() }
                    }
            } else {
                Label(screen.name, systemImage: Self.symbol(for: screen.kind))
            }
        }
        .padding(.leading, inGroup ? 10 : 0)
        .contextMenu { screenMenu(screen) }
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
                Text("×")
                TextField(
                    "Height",
                    value: Binding(
                        get: { screen.viewport.height },
                        set: { controller.setSize(width: screen.viewport.width, height: $0, of: id) }),
                    format: .number.grouping(.never)
                )
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
                    Text("×")
                    TextField(
                        "Content height",
                        value: Binding(
                            get: { scroll.contentHeight }, set: { controller.setScroll(height: $0, of: id) }),
                        format: .number.grouping(.never)
                    )
                    Text("pt")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .controlSize(.small)
        .padding(10)
    }
}
