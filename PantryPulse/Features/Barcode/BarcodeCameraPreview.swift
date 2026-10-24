import SwiftUI
import AVFoundation

struct BarcodeCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = session
        return view
    }
    func updateUIView(_ uiView: PreviewView, context: Context) {}
    static func dismantleUIView(_ uiView: PreviewView, coordinator: ()) { uiView.previewLayer.session = nil }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        override func layoutSubviews() {
            super.layoutSubviews()
            guard let connection = previewLayer.connection else { return }
            let angle: CGFloat
            switch window?.windowScene?.interfaceOrientation {
            case .landscapeLeft: angle = 0
            case .landscapeRight: angle = 180
            case .portraitUpsideDown: angle = 270
            default: angle = 90
            }
            if connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
        }
    }
}
