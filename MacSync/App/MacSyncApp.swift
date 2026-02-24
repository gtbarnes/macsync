import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct MacSyncApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup("MacSync") {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear {
                    appState.initialize()
                }
                .task {
                    await appState.checkPermissionsOnLaunch()
                }
                .alert("Full Disk Access Required", isPresented: $appState.showFullDiskAccessAlert) {
                    Button("Open System Settings") {
                        PermissionService.shared.openFullDiskAccessSettings()
                    }
                    Button("Later", role: .cancel) { }
                } message: {
                    Text("MacSync needs Full Disk Access to read and sync files across your system. Please enable it in System Settings → Privacy & Security → Full Disk Access.")
                }
                .alert("Cannot Access Path", isPresented: $appState.showPathAccessAlert) {
                    Button("Open System Settings") {
                        PermissionService.shared.openFullDiskAccessSettings()
                    }
                    Button("OK", role: .cancel) { }
                } message: {
                    Text(appState.pathAccessAlertMessage)
                }
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1400, height: 900)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Sync Profile...") {
                    appState.showNewProfileSheet = true
                }
                .keyboardShortcut("n")
            }
            CommandMenu("View") {
                Button("Toggle Inspector") {
                    appState.showInspector.toggle()
                }
                .keyboardShortcut("i", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
