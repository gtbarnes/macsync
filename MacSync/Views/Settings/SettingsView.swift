import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("globalThreadLimit") var threadLimit: Int = 4
    @AppStorage("showInspector") var showInspector: Bool = false

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gear") }
            rsyncTab.tabItem { Label("rsync", systemImage: "terminal") }
        }
        .frame(width: 450, height: 300)
    }

    private var generalTab: some View {
        Form {
            Section("Performance") {
                Stepper("Default Thread Count: \(threadLimit)", value: $threadLimit, in: 1...32)
                Text("Parallel rsync processes per sync task").font(.caption).foregroundStyle(.secondary)
            }
            Section("Appearance") {
                Toggle("Show Inspector by Default", isOn: $showInspector)
            }
        }.formStyle(.grouped)
    }

    private var rsyncTab: some View {
        Form {
            Section("rsync Binary") {
                LabeledContent("Path", value: RsyncBinary.path)
                LabeledContent("Version", value: RsyncBinary.version)
            }
        }.formStyle(.grouped)
    }
}
