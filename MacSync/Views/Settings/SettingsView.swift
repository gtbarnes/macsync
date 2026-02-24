import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Text("Settings")
        }
        .frame(width: 400, height: 200)
    }
}
