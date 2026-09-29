import SwiftUI

@main
struct InnerPeekApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 12) {
                Image(systemName: "folder.badge.questionmark")
                    .font(.system(size: 42))
                Text("InnerPeek")
                    .font(.title2.weight(.semibold))
                Text("The Quick Look extension is installed and ready.")
                    .foregroundStyle(.secondary)
            }
            .frame(width: 360, height: 220)
            .padding()
        }
    }
}
