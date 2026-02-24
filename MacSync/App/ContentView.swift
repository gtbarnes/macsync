import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            ComparisonView()
                .toolbar {
                    toolbarContent
                }
                .inspector(isPresented: $appState.showInspector) {
                    InspectorView()
                        .inspectorColumnWidth(min: 260, ideal: 300, max: 400)
                }
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $appState.showNewProfileSheet) {
            Text("Profile Editor - Coming Soon")
                .frame(width: 500, height: 400)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            Button { appState.showNewProfileSheet = true } label: {
                Label("New Task", systemImage: "plus")
            }

            Button { appState.startSelectedTask() } label: {
                Label("Start", systemImage: "play.fill")
            }
            .disabled(appState.selectedProfile == nil)

            Button { appState.pauseSelectedTask() } label: {
                Label("Pause", systemImage: "pause.fill")
            }
            .disabled(appState.selectedTaskIsNotRunning)

            Button { appState.stopSelectedTask() } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .disabled(appState.selectedTaskIsNotRunning)
        }

        ToolbarItem(placement: .automatic) {
            HStack(spacing: 4) {
                Text("Threads:")
                    .font(.caption)
                Stepper(value: $appState.globalThreadLimit, in: 1...32) {
                    Text("\(appState.globalThreadLimit)")
                        .monospacedDigit()
                }
            }
        }

        ToolbarItem(placement: .automatic) {
            Button {
                appState.showInspector.toggle()
            } label: {
                Label("Inspector", systemImage: "sidebar.right")
            }
        }
    }
}
