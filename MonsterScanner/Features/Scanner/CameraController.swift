@preconcurrency import AVFoundation
import MonsterCore
import Vision

/// Owns the AVCaptureSession. All session work happens on `sessionQueue`;
/// live face detection runs on `videoQueue`. Marked `@unchecked Sendable`
/// because those queues serialise every access to the AVFoundation objects.
nonisolated final class CameraController: NSObject, @unchecked Sendable, AVCaptureVideoDataOutputSampleBufferDelegate {
    enum CameraError: Error { case noCamera, cannotAddInput, cannotAddOutput, noPhotoData }

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "monster.camera.session")
    private let videoQueue = DispatchQueue(label: "monster.camera.video")
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private var currentInput: AVCaptureDeviceInput?
    private var isConfigured = false
    private var inFlight: [Int64: PhotoCaptureDelegate] = [:]
    private var lastDetection = Date.distantPast

    /// Upright face boxes (top-left origin, largest first) and the frame
    /// aspect ratio (width ÷ height). Called on the video queue. Set once,
    /// before `start`.
    private let faceHandler: @Sendable ([UnitRect], Double) -> Void

    init(faceHandler: @escaping @Sendable ([UnitRect], Double) -> Void) {
        self.faceHandler = faceHandler
        super.init()
    }

    static var hasCamera: Bool { AVCaptureDevice.default(for: .video) != nil }

    static func hasTorch(position: AVCaptureDevice.Position) -> Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)?.hasTorch ?? false
    }

    // MARK: Session

    func start(position: AVCaptureDevice.Position) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                do {
                    try self.configure(position: position)
                    if !self.session.isRunning { self.session.startRunning() }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() {
        sessionQueue.async {
            self.applyTorch(false)
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    private func configure(position: AVCaptureDevice.Position) throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        if !isConfigured {
            session.sessionPreset = .photo
            guard session.canAddOutput(photoOutput) else { throw CameraError.cannotAddOutput }
            session.addOutput(photoOutput)
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            ]
            videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
            guard session.canAddOutput(videoOutput) else { throw CameraError.cannotAddOutput }
            session.addOutput(videoOutput)
            isConfigured = true
        }

        if currentInput?.device.position != position {
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
                throw CameraError.noCamera
            }
            applyTorch(false)
            let input = try AVCaptureDeviceInput(device: device)
            if let currentInput { session.removeInput(currentInput) }
            guard session.canAddInput(input) else { throw CameraError.cannotAddInput }
            session.addInput(input)
            currentInput = input

            // A ~2-4 MP photo is plenty (it is downscaled to 1024 px anyway)
            // and captures faster than full resolution.
            let sizes = device.activeFormat.supportedMaxPhotoDimensions
            if let size = sizes.filter({ max($0.width, $0.height) >= 1600 })
                .min(by: { $0.width * $0.height < $1.width * $1.height }) ?? sizes.first {
                photoOutput.maxPhotoDimensions = size
            }
        }

        // Portrait, and mirrored on the front camera to match the preview.
        for output in [photoOutput, videoOutput] as [AVCaptureOutput] {
            guard let connection = output.connection(with: .video) else { continue }
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = position == .front
            }
        }
    }

    // MARK: Torch ("UV lamp" on the back camera)

    func setTorch(_ on: Bool) {
        sessionQueue.async { self.applyTorch(on) }
    }

    private func applyTorch(_ on: Bool) {
        guard let device = currentInput?.device, device.hasTorch, device.isTorchAvailable else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        } catch {
            DebugLog.shared.record("Torch failed: \(error.localizedDescription)")
        }
    }

    // MARK: Photo

    func capturePhoto() async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            sessionQueue.async {
                let settings = AVCapturePhotoSettings()
                settings.maxPhotoDimensions = self.photoOutput.maxPhotoDimensions
                settings.photoQualityPrioritization = .balanced
                settings.flashMode = .off
                let id = settings.uniqueID
                // The delegate holds `self` only until the capture finishes.
                let delegate = PhotoCaptureDelegate { result in
                    self.sessionQueue.async { self.inFlight[id] = nil }
                    continuation.resume(with: result)
                }
                self.inFlight[id] = delegate
                self.photoOutput.capturePhoto(with: settings, delegate: delegate)
            }
        }
    }

    // MARK: Live face reticle

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = Date()
        guard now.timeIntervalSince(lastDetection) > 0.12,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastDetection = now
        let request = VNDetectFaceRectanglesRequest()
        try? VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up).perform([request])
        let boxes = (request.results ?? [])
            .map { FaceAnalyzer.topLeft($0.boundingBox) }
            .sorted { $0.area > $1.area }
        let aspect = Double(CVPixelBufferGetWidth(buffer)) / Double(max(1, CVPixelBufferGetHeight(buffer)))
        faceHandler(boxes, aspect)
    }
}

/// Bridges one photo capture back to async/await.
nonisolated private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private let completion: @Sendable (Result<Data, Error>) -> Void

    init(completion: @escaping @Sendable (Result<Data, Error>) -> Void) {
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            completion(.failure(error))
        } else if let data = photo.fileDataRepresentation() {
            completion(.success(data))
        } else {
            completion(.failure(CameraController.CameraError.noPhotoData))
        }
    }
}
