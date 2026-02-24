import SwiftUI
import AppKit

struct ProfileEditorView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var sourcePath: String = ""
    @State private var destinationPath: String = ""
    @State private var syncMode: SyncMode = .mirror
    @State private var deletionPolicy: DeletionPolicyChoice = .trash
    @State private var versioningPath: String = ""
    @State private var threadCount: Int = 4
    @State private var excludePatterns: String = ".DS_Store\nThumbs.db\n.macsync_partial/\n._*"

    /// Simplified deletion policy for picker (avoids associated value complexity)
    private enum DeletionPolicyChoice: String, CaseIterable, Identifiable {
        case trash = "Move to Trash"
        case versioning = "Versioning Folder"
        case permanent = "Permanent Delete"
        var id: String { rawValue }
    }

    /// If editing an existing profile, populate state from it
    var editingProfile: SyncProfile? {
        appState.editingProfile
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                // MARK: - Name
                Section("Profile Name") {
                    TextField("Profile Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                // MARK: - Paths
                Section("Paths") {
                    HStack {
                        TextField("Source Path", text: $sourcePath)
                            .textFieldStyle(.roundedBorder)
                        Button("Browse\u{2026}") {
                            browseFolder(for: $sourcePath)
                        }
                    }
                    HStack {
                        TextField("Destination Path", text: $destinationPath)
                            .textFieldStyle(.roundedBorder)
                        Button("Browse\u{2026}") {
                            browseFolder(for: $destinationPath)
                        }
                    }
                }

                // MARK: - Sync Mode
                Section("Sync Mode") {
                    Picker("Mode", selection: $syncMode) {
                        ForEach(SyncMode.allCases) { mode in
                            VStack(alignment: .leading) {
                                Label(mode.displayName, systemImage: mode.systemImage)
                            }
                            .tag(mode)
                        }
                    }
                    .pickerStyle(.radioGroup)

                    Text(syncMode.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // MARK: - Deletion Policy
                Section("Deletion Policy") {
                    Picker("Policy", selection: $deletionPolicy) {
                        ForEach(DeletionPolicyChoice.allCases) { choice in
                            Text(choice.rawValue).tag(choice)
                        }
                    }
                    .pickerStyle(.radioGroup)

                    if deletionPolicy == .versioning {
                        HStack {
                            TextField("Versioning Folder Path", text: $versioningPath)
                                .textFieldStyle(.roundedBorder)
                            Button("Browse\u{2026}") {
                                browseFolder(for: $versioningPath)
                            }
                        }
                    }
                }

                // MARK: - Threads
                Section("Performance") {
                    Stepper("Thread Count: \(threadCount)", value: $threadCount, in: 1...32)
                }

                // MARK: - Exclude Patterns
                Section("Exclude Patterns (one per line)") {
                    TextEditor(text: $excludePatterns)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 80, maxHeight: 120)
                        .border(Color.secondary.opacity(0.3), width: 1)
                }
            }
            .formStyle(.grouped)
            .padding(.bottom, 8)

            // MARK: - Buttons
            Divider()
            HStack {
                Spacer()
                Button("Cancel") {
                    appState.editingProfile = nil
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || sourcePath.isEmpty || destinationPath.isEmpty)
            }
            .padding()
        }
        .frame(width: 520, height: 580)
        .onAppear {
            if let profile = editingProfile {
                name = profile.name
                sourcePath = profile.sourcePath
                destinationPath = profile.destinationPath
                syncMode = profile.syncMode
                threadCount = profile.threadCount
                excludePatterns = profile.filters.excludePatterns.joined(separator: "\n")
                switch profile.deletionPolicy {
                case .trash:
                    deletionPolicy = .trash
                case .versioning(let path):
                    deletionPolicy = .versioning
                    versioningPath = path
                case .permanent:
                    deletionPolicy = .permanent
                }
            }
        }
    }

    // MARK: - Actions

    private func browseFolder(for binding: Binding<String>) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            binding.wrappedValue = url.path
        }
    }

    private func save() {
        let resolvedDeletionPolicy: DeletionPolicy = {
            switch deletionPolicy {
            case .trash: return .trash
            case .versioning: return .versioning(path: versioningPath)
            case .permanent: return .permanent
            }
        }()

        let patterns = excludePatterns
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)

        if var existing = editingProfile {
            existing.name = name
            existing.sourcePath = sourcePath
            existing.destinationPath = destinationPath
            existing.syncMode = syncMode
            existing.deletionPolicy = resolvedDeletionPolicy
            existing.threadCount = threadCount
            existing.filters.excludePatterns = patterns
            appState.saveProfile(existing)
        } else {
            var profile = SyncProfile(
                name: name,
                sourcePath: sourcePath,
                destinationPath: destinationPath,
                syncMode: syncMode,
                deletionPolicy: resolvedDeletionPolicy,
                threadCount: threadCount
            )
            profile.filters.excludePatterns = patterns
            appState.saveProfile(profile)
        }

        appState.editingProfile = nil
        dismiss()
    }
}
