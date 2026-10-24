import Foundation

nonisolated protocol ProductLookupService: Sendable {
    func lookup(barcode: String) async throws -> ProductLookupResult
    func lookup(scan: ScannedBarcode) async throws -> ProductLookupResult
}

extension ProductLookupService {
    nonisolated func lookup(scan: ScannedBarcode) async throws -> ProductLookupResult {
        try await lookup(barcode: scan.rawValue)
    }
}

nonisolated enum ProductLookupError: Error, LocalizedError, Equatable {
    case invalidBarcode, productNotFound, invalidResponse, timedOut, rateLimited
    case httpStatus(Int)
    case network(URLError.Code)

    var errorDescription: String? {
        switch self {
        case .invalidBarcode: "Check the barcode digits and check digit, or scan the barcode again."
        case .productNotFound: "Product not found in our databases."
        case .invalidResponse: "Open Food Facts returned an unreadable product response. Please try again."
        case .timedOut: "The product lookup timed out. Please try again."
        case .rateLimited: "Too many product lookups. Please wait before trying again."
        case .httpStatus(let status): "The product service is unavailable (HTTP \(status)). Please try again later."
        case .network: "Unable to connect to Open Food Facts. Check your connection and try again."
        }
    }
}

/// No persistence side effects. Callers must let the user confirm inventory fields before saving.
nonisolated struct OpenFoodFactsService: ProductLookupService {
    private let session: URLSession
    private let userAgent: String

    init(session: URLSession = .shared,
         userAgent: String = "PantryPulse/1.0 (https://github.com/ThisajaM/PantryPulse)") {
        self.session = session
        self.userAgent = userAgent
    }

    func lookup(barcode: String) async throws -> ProductLookupResult {
        try Task.checkCancellation()
        // Validate format without converting to a number or stripping leading zeroes.
        // Check digits are left to the catalogue: eight-digit codes can also be UPC-E.
        guard [8, 12, 13, 14].contains(barcode.utf8.count),
              barcode.utf8.allSatisfy({ (48...57).contains($0) }) else {
            throw ProductLookupError.invalidBarcode
        }
        guard var components = URLComponents(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json") else {
            throw ProductLookupError.invalidBarcode
        }
        components.queryItems = [URLQueryItem(name: "fields", value:
            "product_name,brands,quantity,categories,categories_tags,image_front_url,image_url")]
        guard let url = components.url else { throw ProductLookupError.invalidBarcode }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            if error.code == .timedOut { throw ProductLookupError.timedOut }
            throw ProductLookupError.network(error.code)
        }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw ProductLookupError.invalidResponse }
        switch http.statusCode {
        case 200..<300: break
        case 404: throw ProductLookupError.productNotFound
        case 429: throw ProductLookupError.rateLimited
        default: throw ProductLookupError.httpStatus(http.statusCode)
        }
        let decoded: ProductResponse
        do { decoded = try JSONDecoder().decode(ProductResponse.self, from: data) }
        catch { throw ProductLookupError.invalidResponse }
        if decoded.status == 0 { throw ProductLookupError.productNotFound }
        guard decoded.status == 1, let product = decoded.product else { throw ProductLookupError.invalidResponse }
        return ProductLookupResult(barcode: barcode, name: clean(product.product_name),
                                   brand: clean(product.brands), quantityText: clean(product.quantity),
                                   categoryText: clean(product.categories),
                                   categoryTags: (product.categories_tags ?? []).compactMap(clean),
                                   imageURL: imageURL(product.image_front_url) ?? imageURL(product.image_url))
    }

    private func clean(_ value: String?) -> String? {
        guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    private func imageURL(_ value: String?) -> URL? {
        guard let text = clean(value), let url = URL(string: text),
              url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else { return nil }
        return url
    }
}

private nonisolated struct ProductResponse: Codable {
    let status: Int
    let product: ProductFields?
}

private nonisolated struct ProductFields: Codable {
    let product_name: String?
    let brands: String?
    let quantity: String?
    let categories: String?
    let categories_tags: [String]?
    let image_front_url: String?
    let image_url: String?
}
