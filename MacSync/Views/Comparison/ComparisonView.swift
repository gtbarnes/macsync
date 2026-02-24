import SwiftUI

struct ComparisonView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Select a profile")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
