import SwiftUI

/// Switches between the game's screens.
struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var app = app
        ZStack {
            Theme.background.ignoresSafeArea()
            switch app.screen {
            case .boot:
                BootView()
            case .consent:
                ConsentView(onAccept: app.acceptConsent)
            case .scanner:
                ScannerView()
            case .scanning:
                if let session = app.session { ScanningView(session: session) }
            case .noSubject:
                NoSubjectView()
            case .reveal:
                if let session = app.session { RevealView(session: session) }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: app.screen)
        .onAppear {
            app.haptics.prepare()
            SoundFX.shared.prepare()
            #if DEBUG
            app.applyDebugLaunchArguments()
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await app.models.prepare() }
            case .background:
                app.narrator.stop()
                app.models.unload(reason: "app in background")
            default:
                app.narrator.stop()
            }
        }
        .alert(
            "Scanner error",
            isPresented: Binding(get: { app.alertMessage != nil }, set: { if !$0 { app.alertMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(app.alertMessage ?? "")
        }
    }
}
