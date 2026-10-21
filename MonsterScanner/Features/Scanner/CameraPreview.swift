import AVFoundation
import MonsterCore
import SwiftUI

/// Live camera preview (aspect fill, portrait).
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        override func layoutSubviews() {
            super.layoutSubviews()
            if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }
    }
}

/// Maps a normalised box in an image of `aspect` (w ÷ h) onto a view of
/// `size`, for either aspect-fill (camera preview) or aspect-fit (photo).
enum BoxMapper {
    static func rect(for box: UnitRect, aspect: Double, in size: CGSize, fill: Bool) -> CGRect {
        let viewW = Double(size.width), viewH = Double(size.height)
        guard viewW > 0, viewH > 0, aspect > 0 else { return .zero }
        let scale = fill ? max(viewW / aspect, viewH) : min(viewW / aspect, viewH)
        let imageW = aspect * scale, imageH = scale
        let offsetX = (viewW - imageW) / 2, offsetY = (viewH - imageH) / 2
        return CGRect(
            x: offsetX + box.x * imageW, y: offsetY + box.y * imageH,
            width: box.width * imageW, height: box.height * imageH
        )
    }
}

/// Targeting brackets drawn around a face.
struct Reticle: View {
    var color: Color = Theme.neon
    var label: String?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let arm = min(w, h) * 0.22
            Path { p in
                for (x, y, dx, dy) in [(0.0, 0.0, 1.0, 1.0), (w, 0, -1, 1), (0, h, 1, -1), (w, h, -1, -1)] {
                    p.move(to: CGPoint(x: x + dx * arm, y: y))
                    p.addLine(to: CGPoint(x: x, y: y))
                    p.addLine(to: CGPoint(x: x, y: y + dy * arm))
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .square))
            .crtGlow(color, radius: 5)
            if let label {
                Text(label)
                    .font(Theme.mono(.caption2, weight: .bold))
                    .foregroundStyle(color)
                    .padding(.horizontal, 4)
                    .background(Color.black.opacity(0.6))
                    .offset(y: -18)
            }
        }
        .accessibilityHidden(true)
    }
}
