import SwiftUI
import UIKit

/// A separate scene window also covers sheets and camera presentations while locked.
struct AppPrivacyShield: UIViewRepresentable {
    let lock: AppLock
    let phase: ScenePhase
    let session: AccountSession

    func makeUIView(context: Context) -> UIView { UIView() }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func updateUIView(_ view: UIView, context: Context) {
        let shouldCover = lock.locked || (lock.enabled && phase != .active)
        let coordinator = context.coordinator
        DispatchQueue.main.async { [weak view] in
            guard let scene = view?.window?.windowScene else { return }
            coordinator.update(scene: scene, lock: lock, session: session, cover: shouldCover)
        }
    }
    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) { coordinator.hide() }

    @MainActor
    final class Coordinator {
        private var window: UIWindow?
        func update(scene: UIWindowScene, lock: AppLock, session: AccountSession, cover: Bool) {
            guard cover else { hide(); return }
            if window == nil {
                scene.windows.forEach { $0.endEditing(true) }
                let window = UIWindow(windowScene: scene)
                window.windowLevel = .alert + 1
                self.window = window
            }
            window?.rootViewController = UIHostingController(rootView: AppLockOverlay().environment(lock).environment(session))
            window?.rootViewController?.view.accessibilityViewIsModal = true
            window?.isHidden = false
        }
        func hide() { window?.isHidden = true; window?.rootViewController = nil; window = nil }
    }
}
