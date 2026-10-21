import AVFoundation
import MonsterCore
import Observation
import UIKit

/// Main-actor face of the camera for SwiftUI.
@Observable
final class CameraModel {
    enum Status: Equatable { case idle, starting, running, denied, unavailable, failed }

    private(set) var status: Status = .idle
    private(set) var faces: [UnitRect] = []
    /// Frame width ÷ height of the live video, for mapping face boxes.
    private(set) var frameAspect: Double = 3.0 / 4.0
    private(set) var position: AVCaptureDevice.Position = .back
    private(set) var isCapturing = false
    /// Player's "UV lamp" switch: torch on the back camera, screen glow on the
    /// front (DECISIONS.md S-1).
    var uvLampOn = false { didSet { applyUVLamp() } }

    @ObservationIgnored private(set) var controller: CameraController!
    @ObservationIgnored private var savedBrightness: CGFloat?

    init() {
        controller = CameraController { [weak self] faces, aspect in
            Task { @MainActor in
                guard let self, self.status == .running else { return }
                self.faces = faces
                self.frameAspect = aspect
            }
        }
    }

    /// True when the front-camera screen glow should be drawn.
    var showsScreenGlow: Bool { uvLampOn && position == .front }

    func start() async {
        guard status != .running, status != .starting else { return }
        guard CameraController.hasCamera else { status = .unavailable; return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { status = .denied; return }
        default:
            status = .denied
            return
        }
        status = .starting
        do {
            try await controller.start(position: position)
            status = .running
            applyUVLamp()
        } catch {
            DebugLog.shared.record("Camera start failed: \(error)")
            status = .failed
        }
    }

    func stop() {
        setScreenGlow(false)
        controller.stop()
        faces = []
        if status == .running || status == .starting { status = .idle }
    }

    func flip() async {
        position = position == .back ? .front : .back
        faces = []
        do {
            try await controller.start(position: position)
            applyUVLamp()
        } catch {
            DebugLog.shared.record("Camera flip failed: \(error)")
            status = .failed
        }
    }

    func capture() async -> Data? {
        guard status == .running, !isCapturing else { return nil }
        isCapturing = true
        defer { isCapturing = false }
        do {
            return try await controller.capturePhoto()
        } catch {
            DebugLog.shared.record("Capture failed: \(error)")
            return nil
        }
    }

    // MARK: UV lamp

    private func applyUVLamp() {
        controller.setTorch(uvLampOn && position == .back && status == .running)
        setScreenGlow(showsScreenGlow)
    }

    private func setScreenGlow(_ on: Bool) {
        guard let screen = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen else { return }
        if on {
            if savedBrightness == nil { savedBrightness = screen.brightness }
            screen.brightness = 1
        } else if let saved = savedBrightness {
            screen.brightness = saved
            savedBrightness = nil
        }
    }
}
