import PhotosUI
import SwiftUI

/// Live camera with face reticle, UV lamp, front/back switch, photo import
/// and a big pulsing shutter.
struct ScannerView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @State private var camera = CameraModel()
    @State private var pickerItem: PhotosPickerItem?
    @State private var showingSettings = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            if camera.showsScreenGlow { Theme.uvGlow.ignoresSafeArea() }

            viewfinder
                .padding(camera.showsScreenGlow ? 36 : 0)
                .ignoresSafeArea(edges: camera.showsScreenGlow ? [] : .all)

            VStack {
                topBar
                Spacer()
                statusLine
                bottomBar
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .background(Color.black.ignoresSafeArea())
        .task { await camera.start() }
        .onDisappear { camera.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await camera.start() }
            } else {
                camera.uvLampOn = false
                camera.stop()
            }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await importPhoto(item) }
        }
        .sheet(isPresented: $showingSettings) { SettingsView() }
    }

    // MARK: Viewfinder

    @ViewBuilder
    private var viewfinder: some View {
        switch camera.status {
        case .running, .starting:
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    CameraPreview(session: camera.controller.session)
                    ForEach(Array(camera.faces.prefix(4).enumerated()), id: \.offset) { index, face in
                        let rect = BoxMapper.rect(for: face, aspect: camera.frameAspect, in: geo.size, fill: true)
                        Reticle(
                            color: index == 0 ? Theme.neon : Theme.dimNeon,
                            label: index == 0 ? "SUBJECT" : nil
                        )
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                        .animation(.easeOut(duration: 0.12), value: face)
                    }
                    ScanLines(opacity: 0.12)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(camera.faces.isEmpty ? "Camera viewfinder. No subject in view." : "Camera viewfinder. Subject in view.")
        case .denied:
            noCameraMessage(
                title: "CAMERA ACCESS DENIED",
                text: "The scanner needs the camera to scan a friend. You can turn it on in Settings, or import a photo instead.",
                showsSettingsLink: true
            )
        case .unavailable:
            noCameraMessage(
                title: "NO CAMERA DETECTED",
                text: "This device has no camera (are you in the Simulator?). Import a photo instead.",
                showsSettingsLink: false
            )
        case .failed:
            noCameraMessage(
                title: "CAMERA MALFUNCTION",
                text: "The camera wouldn't start. Try again, or import a photo instead.",
                showsSettingsLink: false
            )
        case .idle:
            Color.black
        }
    }

    private func noCameraMessage(title: String, text: String, showsSettingsLink: Bool) -> some View {
        VStack(spacing: 18) {
            Spacer()
            Text("📷❌").font(.system(size: 54))
            Text(title)
                .font(Theme.mono(.headline, weight: .bold))
                .foregroundStyle(Theme.alert)
            Text(text)
                .font(Theme.mono(.callout))
                .foregroundStyle(Theme.neon)
                .multilineTextAlignment(.center)
            if showsSettingsLink {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(NeonButtonStyle())
                .frame(maxWidth: 260)
            }
            Spacer()
            Spacer()
        }
        .padding(28)
        .crtScreen()
    }

    // MARK: Controls

    private var topBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("FIELD SCANNER")
                    .font(Theme.mono(.headline, weight: .bold))
                    .foregroundStyle(Theme.neon)
                    .crtGlow()
                Text(ModelService.isTooHot ? "OVERHEATING · BACKUP CRYSTALS"
                     : app.models.observerForScan != nil ? "MODE: AI OBSERVER" : "MODE: CLASSIC")
                    .font(Theme.mono(.caption2))
                    .foregroundStyle(Theme.dimNeon)
            }
            Spacer()
            if camera.status == .running {
                Button {
                    camera.uvLampOn.toggle()
                } label: {
                    Image(systemName: camera.uvLampOn ? "lightbulb.max.fill" : "lightbulb")
                }
                .buttonStyle(IconButtonStyle(active: camera.uvLampOn))
                .accessibilityLabel(camera.position == .back ? "UV lamp (torch)" : "UV glow (screen light)")
                .accessibilityValue(camera.uvLampOn ? "On" : "Off")

                Button {
                    Task { await camera.flip() }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                }
                .buttonStyle(IconButtonStyle())
                .accessibilityLabel(camera.position == .back ? "Switch to front camera" : "Switch to back camera")
            }
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(IconButtonStyle())
            .accessibilityLabel("Settings")
        }
        .padding(.top, 8)
    }

    private var statusLine: some View {
        Group {
            switch camera.status {
            case .running:
                Text(camera.faces.isEmpty ? "SEARCHING FOR SUBJECT…" : camera.faces.count > 1 ? "\(camera.faces.count) SUBJECTS · LARGEST LOCKED" : "SUBJECT ACQUIRED")
            case .starting:
                Text("WARMING UP LENSES…")
            default:
                Text("IMPORT A PHOTO TO SCAN")
            }
        }
        .font(Theme.mono(.caption, weight: .bold))
        .foregroundStyle(Theme.neon)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.black.opacity(0.6))
        .padding(.bottom, 14)
    }

    private var bottomBar: some View {
        HStack(alignment: .center) {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Image(systemName: "photo.on.rectangle")
            }
            .buttonStyle(IconButtonStyle())
            .accessibilityLabel("Import a photo")

            Spacer()
            shutter
            Spacer()

            Color.clear.frame(width: 44, height: 44)
        }
    }

    private var shutter: some View {
        Button {
            Task { await takePhoto() }
        } label: {
            ZStack {
                Circle()
                    .stroke(Theme.neon, lineWidth: 4)
                    .frame(width: 86, height: 86)
                    .scaleEffect(pulse ? 1.12 : 1)
                    .opacity(pulse ? 0.35 : 1)
                Circle()
                    .fill(Theme.alert)
                    .frame(width: 68, height: 68)
                    .overlay(Text("SCAN").font(Theme.mono(.caption, weight: .heavy)).foregroundStyle(.white))
            }
            .crtGlow(Theme.alert, radius: 10)
        }
        .buttonStyle(.plain)
        .disabled(camera.status != .running || camera.isCapturing)
        .opacity(camera.status == .running ? 1 : 0.35)
        .accessibilityLabel("Scan")
        .accessibilityHint("Takes a photo and starts the monster scan")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) { pulse = true }
        }
    }

    // MARK: Actions

    private func takePhoto() async {
        if app.hapticsEnabled { app.haptics.tap() }
        guard let data = await camera.capture() else {
            app.alertMessage = "The shutter jammed. Try again."
            return
        }
        camera.uvLampOn = false
        app.startScan(data: data, source: .camera)
    }

    private func importPhoto(_ item: PhotosPickerItem) async {
        defer { pickerItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                app.alertMessage = "That photo couldn't be loaded."
                return
            }
            app.startScan(data: data, source: .library)
        } catch {
            DebugLog.shared.record("Photo import failed: \(error.localizedDescription)")
            app.alertMessage = "That photo couldn't be loaded."
        }
    }
}
