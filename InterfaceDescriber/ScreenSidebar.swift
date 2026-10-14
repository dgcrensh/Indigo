import DescriberCore
import SwiftUI

/// The screens of the project in sidebar order. Selecting one makes it the active screen. Adding, renaming,
/// reordering and deleting screens arrive in milestone 8.
struct ScreenSidebar: View {
    @Bindable var model: DocumentModel

    var body: some View {
        List(selection: $model.activeScreenID) {
            ForEach(model.project.screens, id: \.id) { screen in
                Text(screen.name)
                    .tag(Optional(screen.id))
            }
        }
        .listStyle(.sidebar)
    }
}
