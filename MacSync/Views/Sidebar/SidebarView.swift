import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        List {
            Text("Profiles")
                .font(.headline)
        }
        .listStyle(.sidebar)
    }
}
