import SwiftUI
import AVFoundation

/// Permission is requested only following an explicit camera or recognition action.
enum FoodCameraAccess {
    enum Decision: Equatable { case available, requestPermission, denied, unavailable }
    static func decision(available: Bool, status: AVAuthorizationStatus) -> Decision {
        guard available else { return .unavailable }
        switch status {
        case .authorized: return .available
        case .notDetermined: return .requestPermission
        default: return .denied
        }
    }
}

struct FoodCameraPicker: UIViewControllerRepresentable {
    var onLibrary: (() -> Void)? = nil
    let completion: (UIImage?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        picker.showsCameraControls = true
        // Keep Apple's capture/cancel controls and camera lifecycle intact.
        if let onLibrary {
            let button = UIButton(type: .system)
            var configuration = UIButton.Configuration.filled()
            configuration.title = "Photo Library"
            configuration.image = UIImage(systemName: "photo.on.rectangle")
            configuration.imagePadding = 8
            configuration.baseForegroundColor = .white
            configuration.baseBackgroundColor = .black.withAlphaComponent(0.65)
            configuration.cornerStyle = .capsule
            button.configuration = configuration
            button.accessibilityLabel = "Choose from Photo Library"
            let overlay = CameraOverlayView(frame: picker.view.bounds)
            overlay.backgroundColor = .clear
            overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            button.translatesAutoresizingMaskIntoConstraints = false
            overlay.addSubview(button)
            NSLayoutConstraint.activate([
                button.leadingAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.leadingAnchor, constant: 16),
                button.topAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.topAnchor, constant: 16),
                button.widthAnchor.constraint(equalToConstant: 190),
                button.heightAnchor.constraint(equalToConstant: 52)
            ])
            button.addAction(UIAction { _ in onLibrary() }, for: .touchUpInside)
            // UIImagePickerController owns its child hierarchy. A standalone UIKit
            // overlay must not be inserted as another navigation child controller.
            picker.cameraOverlayView = overlay

        }
        return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private var delivered = false
        let completion: (UIImage?) -> Void
        init(completion: @escaping (UIImage?) -> Void) { self.completion = completion }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { completion(nil) }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard !delivered else { return }
            delivered = true
            completion(info[.originalImage] as? UIImage)
        }
    }
}

/// Camera overlays may be resized by UIKit. Only the gallery button consumes touches.
private final class CameraOverlayView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}
