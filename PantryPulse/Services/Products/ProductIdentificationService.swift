import Foundation

/// Optional boundary for an authorized search API/proxy. No search provider is enabled by default.
nonisolated protocol BarcodeCandidateSearching: Sendable {
    func candidate(for barcode: String) async throws -> ProductSearchCandidate?
}
nonisolated struct ProductSearchCandidate: Sendable {
    let product: ProductLookupResult
    let evidenceURL: URL
    let evidenceText: String
}

/// Local confirmation → Open Food Facts → configured licensed providers → optional search.
/// Missing records and unavailable providers are different outcomes; OCR is a user-driven fallback.
nonisolated struct ProductIdentificationService: ProductLookupService {
    let catalogue: ProductCatalogue
    let primary: any ProductLookupService
    let additionalProviders: [any ProductLookupService]
    let search: (any BarcodeCandidateSearching)?

    init(catalogue: ProductCatalogue = ProductCatalogue(), primary: any ProductLookupService = OpenFoodFactsService(),
         additionalProviders: [any ProductLookupService] = [], search: (any BarcodeCandidateSearching)? = nil) {
        self.catalogue = catalogue; self.primary = primary
        self.additionalProviders = additionalProviders; self.search = search
    }
    func lookup(barcode: String) async throws -> ProductLookupResult {
        try await lookup(scan: ScannedBarcode(rawValue: barcode, symbology: "manual"))
    }
    func lookup(scan: ScannedBarcode) async throws -> ProductLookupResult {
        try Task.checkCancellation()
        let identity = try scan.identity()
        if let local = try catalogue.lookup(scan) { return local }
        var unavailable: Error?
        if let code = identity.globalCode {
            for provider in [primary] + additionalProviders {
                do {
                    var product = try await provider.lookup(barcode: code)
                    try Task.checkCancellation()
                    guard let returned = try? ScannedBarcode(rawValue: product.barcode, symbology: "manual").identity(),
                          returned.key == identity.key else { throw ProductLookupError.invalidResponse }
                    product.barcode = scan.rawValue
                    product.symbology = scan.symbology
                    return product
                } catch is CancellationError { throw CancellationError() }
                catch ProductLookupError.productNotFound { continue }
                catch { if unavailable == nil { unavailable = error } }
            }
        }
        if let search {
            do {
                if let candidate = try await search.candidate(for: scan.rawValue),
                   candidate.product.barcode == scan.rawValue,
                   candidate.evidenceURL.scheme == "https", candidate.evidenceURL.host != nil,
                   candidate.evidenceText.range(of: "(?<![0-9])" + NSRegularExpression.escapedPattern(for: scan.rawValue) + "(?![0-9])", options: .regularExpression) != nil,
                   let name = candidate.product.name, !name.isEmpty,
                   candidate.evidenceText.localizedCaseInsensitiveContains(name) {
                    try Task.checkCancellation()
                    var product = candidate.product
                    product.symbology = scan.symbology
                    product.isSuggestion = true
                    product.dataSource = "Exact-barcode search candidate"
                    product.evidenceURL = candidate.evidenceURL
                    product.usesOpenFoodFactsAttribution = false
                    return product
                }
            } catch is CancellationError { throw CancellationError() }
            catch { if unavailable == nil { unavailable = error } }
        }
        try Task.checkCancellation()
        if let unavailable { throw unavailable }
        throw ProductLookupError.productNotFound
    }
}
