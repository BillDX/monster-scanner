import SwiftUI

@main
struct MonsterScannerApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .preferredColorScheme(.dark)
                .tint(Theme.neon)
        }
    }
}
