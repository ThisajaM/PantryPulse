import AVFoundation
import Observation

@MainActor
@Observable
final class BarcodeCameraModel {
    enum State: Equatable { case idle, starting, running, paused, unavailable, denied, failed(String) }
    private(set) var state: State = .idle
    private(set) var torchEnabled = false
    private let driver: any BarcodeCaptureDriving
    private let available: () -> Bool
    private let authorization: () -> AVAuthorizationStatus
    private let requestPermission: () async -> Bool
    private var generation = 0

    init(driver: any BarcodeCaptureDriving,
         available: @escaping () -> Bool = {
             #if targetEnvironment(simulator)
             false
             #else
             AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
             #endif
         }, authorization: @escaping () -> AVAuthorizationStatus = { AVCaptureDevice.authorizationStatus(for: .video) },
         requestPermission: @escaping () async -> Bool = { await AVCaptureDevice.requestAccess(for: .video) }) {
        self.driver = driver
        self.available = available
        self.authorization = authorization
        self.requestPermission = requestPermission
    }

    private(set) var detectedSymbology = ""

    func start(onBarcode: @escaping (String) -> Void) async {
        stop()
        let token = generation
        state = .starting
        switch FoodCameraAccess.decision(available: available(), status: authorization()) {
        case .unavailable: state = .unavailable; return
        case .denied: state = .denied; return
        case .requestPermission:
            let allowed = await requestPermission()
            guard token == generation, !Task.isCancelled else { return }
            guard allowed else { state = .denied; return }
        case .available: break
        }
        guard token == generation, !Task.isCancelled else { return }
        driver.start { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                switch event {
                case .running: self.state = .running
                case .failed(let message): self.stop(); self.state = .failed(message)
                case .detected(let code, let symbology):
                    self.detectedSymbology = symbology
                    self.stop()
                    self.state = .paused
                    onBarcode(code)
                }
            }
        }
    }

    func stop() {
        generation += 1
        driver.stop()
        torchEnabled = false
        state = .idle
    }

    func toggleTorch() {
        guard state == .running else { return }
        torchEnabled.toggle()
        driver.setTorch(torchEnabled)
    }
}
