import Foundation
import Observation

@MainActor
@Observable
final class BarcodeLookupModel {
    enum State: Equatable { case idle, loading, found(ProductLookupResult), notFound, networkUnavailable(String), serviceUnavailable(String), failed(String) }
    var barcode = ""
    var symbology = ""
    var scan: ScannedBarcode { ScannedBarcode(rawValue: barcode, symbology: symbology) }
    private(set) var state: State = .idle
    private(set) var imageData: Data?
    private(set) var imageError: String?
    private(set) var isLoadingImage = false
    var acceptsImage = true
    @ObservationIgnored private(set) var task: Task<Void, Never>?
    private let service: any ProductLookupService
    private let images: any ProductImageLoading
    private var generation = 0

    init(service: any ProductLookupService = ProductIdentificationService(), images: any ProductImageLoading = ProductImageLoader()) {
        self.service = service
        self.images = images
    }

    func lookup(_ detected: String? = nil) {
        guard state != .loading else { return }
        cancelPending()
        if let detected { barcode = detected }
        let code = detected == nil && symbology != "Code128" ? barcode.trimmingCharacters(in: .whitespacesAndNewlines) : barcode
        barcode = code
        imageData = nil; imageError = nil; acceptsImage = true
        state = .loading
        let token = generation
        let scanned = scan
        task = Task { [weak self, service] in
            do {
                let product = try await service.lookup(scan: scanned)
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.state = .found(product)
                if let local = product.localImageData { self.imageData = local }
                else { await self.loadImage(product.imageURL, token: token) }
            } catch {
                guard let self, self.generation == token, !Task.isCancelled else { return }
                if error is CancellationError { self.state = .idle }
                else if let error = error as? ProductLookupError {
                    switch error {
                    case .productNotFound: self.state = .notFound
                    case .network: self.state = .networkUnavailable(error.localizedDescription)
                    case .rateLimited, .httpStatus, .timedOut, .invalidResponse: self.state = .serviceUnavailable(error.localizedDescription)
                    case .invalidBarcode: self.state = .failed(error.localizedDescription)
                    }
                } else { self.state = .failed(error.localizedDescription) }
            }
        }
    }

    var failureMessage: String? {
        switch state {
        case .notFound: "Product not found in our databases."
        case .networkUnavailable(let text): "Network unavailable. " + text
        case .serviceUnavailable(let text): "Product API temporarily unavailable. " + text
        case .failed(let text): text
        default: nil
        }
    }

    func retryImage() {
        guard case .found(let product) = state, !isLoadingImage else { return }
        let token = generation
        task = Task { [weak self] in await self?.loadImage(product.imageURL, token: token) }
    }

    private func loadImage(_ url: URL?, token: Int) async {
        guard let url else { return }
        isLoadingImage = true
        imageError = nil
        defer { if token == generation { isLoadingImage = false } }
        do {
            let data = try await images.load(url)
            guard token == generation, !Task.isCancelled else { return }
            imageData = data
        } catch {
            guard token == generation, !Task.isCancelled else { return }
            imageError = "The product photo could not be loaded. Retry or continue without it."
        }
    }

    func cancelPending() {
        generation += 1
        task?.cancel()
        task = nil
        if isLoadingImage && imageData == nil {
            imageError = "Photo loading was interrupted. Retry or continue without it."
        }
        isLoadingImage = false
        if state == .loading { state = .idle }
    }

    func reset() {
        cancelPending()
        state = .idle
        imageData = nil; imageError = nil
    }
}
