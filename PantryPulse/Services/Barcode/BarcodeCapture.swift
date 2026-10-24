import AVFoundation
import Vision

nonisolated enum BarcodeCaptureEvent: Sendable {
    case running, detected(String, symbology: String = ""), failed(String)
}

nonisolated protocol BarcodeCaptureDriving: Sendable {
    func start(handler: @escaping @Sendable (BarcodeCaptureEvent) -> Void)
    func stop()
    func setTorch(_ enabled: Bool)
}

/// All mutable capture state, configuration and Vision work are confined to queue.
/// The session is exposed only for attaching an AVCaptureVideoPreviewLayer.
nonisolated final class BarcodeCapture: NSObject, BarcodeCaptureDriving, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    static let supportedSymbologies: [VNBarcodeSymbology] = [.ean13, .ean8, .upce, .code128, .itf14]
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "PantryPulse.barcode.capture", qos: .userInitiated)
    private var handler: (@Sendable (BarcodeCaptureEvent) -> Void)?
    private var configured = false
    private var acceptingFrames = false
    private var lastFrame = -Double.infinity
    private var device: AVCaptureDevice?
    private var observers: [NSObjectProtocol] = []

    func start(handler: @escaping @Sendable (BarcodeCaptureEvent) -> Void) {
        queue.async { [self] in
            self.handler = handler
            do {
                if !configured { try configure() }
                acceptingFrames = true
                lastFrame = -.infinity
                if !session.isRunning { session.startRunning() }
                if session.isRunning { handler(.running) }
                else { fail("The camera could not start. Please retry or enter the barcode manually.") }
            } catch { fail("The camera could not be configured. Please retry or enter the barcode manually.") }
        }
    }

    func stop() {
        queue.async { [self] in
            acceptingFrames = false
            handler = nil
            turnTorchOff()
            if session.isRunning { session.stopRunning() }
        }
    }

    func setTorch(_ enabled: Bool) {
        queue.async { [self] in
            guard let device, device.hasTorch, device.isTorchAvailable else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                device.torchMode = enabled ? .on : .off
            } catch { fail("The camera light is unavailable. Retry scanning without the light.") }
        }
    }

    private func configure() throws {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CaptureError.unavailable
        }
        let input = try AVCaptureDeviceInput(device: camera)
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .hd1280x720
        guard session.canAddInput(input) else { throw CaptureError.unavailable }
        session.addInput(input)
        guard session.canAddOutput(output) else {
            session.removeInput(input)
            throw CaptureError.unavailable
        }
        session.addOutput(output)
        device = camera
        configured = true
        for name in [AVCaptureSession.runtimeErrorNotification, AVCaptureSession.wasInterruptedNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: session, queue: nil) { [weak self] _ in
                guard let self else { return }
                self.queue.async { [self] in
                    guard self.acceptingFrames else { return }
                    self.fail("Camera capture was interrupted. Please retry when the camera is available.")
                }
            })
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard acceptingFrames else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        guard time - lastFrame >= 0.25 else { return }
        lastFrame = time
        let request = VNDetectBarcodesRequest()
        // Vision reports UPC-A as EAN-13 with a leading zero; retain that valid EAN representation.
        do {
            let available = try request.supportedSymbologies()
            request.symbologies = Self.supportedSymbologies.filter { available.contains($0) }
            try VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .right).perform([request])
            guard let observation = request.results?.first(where: { $0.payloadStringValue != nil }),
                  let code = observation.payloadStringValue else { return }
            let symbology = observation.symbology == .code128 ? "Code128" : observation.symbology.rawValue
            acceptingFrames = false
            // Return from the video delegate before stopping its capture pipeline.
            queue.async { [self] in
                turnTorchOff()
                if session.isRunning { session.stopRunning() }
                handler?(.detected(code, symbology: symbology))
            }
        } catch {
            acceptingFrames = false
            queue.async { [self] in fail("This camera frame could not be read. Please retry or enter the barcode manually.") }
        }
    }

    private func fail(_ message: String) {
        acceptingFrames = false
        turnTorchOff()
        if session.isRunning { session.stopRunning() }
        handler?(.failed(message))
    }

    private func turnTorchOff() {
        guard let device, device.hasTorch, device.torchMode == .on else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = .off
            device.unlockForConfiguration()
        } catch { handler?(.failed("The camera light could not be changed.")) }
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    private enum CaptureError: Error { case unavailable }
}
