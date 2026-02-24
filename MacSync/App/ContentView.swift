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
            ProfileEditorView()
                .environmentObject(appState)
        }
        .sheet(isPresented: $appState.showEditProfileSheet) {
            ProfileEditorView()
                .environmentObject(appState)
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
            Button {
                appState.showInspector.toggle()
            } label: {
                Label("Inspector", systemImage: "sidebar.right")
            }
        }
    }
}
