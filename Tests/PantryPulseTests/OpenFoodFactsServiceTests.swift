import Foundation
import Testing
import UIKit
@testable import PantryPulse

@Suite(.serialized)
struct OpenFoodFactsServiceTests {
    private func service(status: Int = 200, body: String = "", error: URLError.Code? = nil,
                         inspect: @escaping @Sendable (URLRequest) -> Void = { _ in }) -> (OpenFoodFactsService, URLSession) {
        ProductHTTPStub.state.set { request in
            inspect(request)
            if let error { throw URLError(error) }
            return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProductHTTPStub.self]
        let session = URLSession(configuration: configuration)
        return (OpenFoodFactsService(session: session), session)
    }

    @Test func mapsProductAndPreservesLeadingZeroes() async throws {
        let (api, session) = service(body: #"{"status":1,"product":{"product_name":" Milk ","brands":" Farm ","quantity":"500 ml","categories":"Dairy","categories_tags":["en:dairies"],"image_front_url":"https://images.openfoodfacts.org/front.jpg"}}"#) { request in
            #expect(request.url?.host == "world.openfoodfacts.org")
            #expect(request.url?.path == "/api/v2/product/0012345678905.json")
            #expect(request.value(forHTTPHeaderField: "User-Agent") == "PantryPulse/1.0 (https://github.com/ThisajaM/PantryPulse)")
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
            #expect(request.timeoutInterval == 20)
        }
        defer { session.invalidateAndCancel() }
        let result = try await api.lookup(barcode: "0012345678905")
        #expect(result.barcode == "0012345678905")
        #expect(result.name == "Milk" && result.brand == "Farm")
        #expect(result.quantityText == "500 ml")
        #expect(result.categoryText == "Dairy" && result.categoryTags == ["en:dairies"])
        #expect(result.imageURL?.absoluteString == "https://images.openfoodfacts.org/front.jpg")
    }

    @Test func partialProductDoesNotInventFields() async throws {
        let (api, session) = service(body: #"{"status":1,"product":{"product_name":"  ","brands":null}}"#)
        defer { session.invalidateAndCancel() }
        let result = try await api.lookup(barcode: "12345678")
        #expect(result.name == nil && result.brand == nil && result.quantityText == nil)
        #expect(result.categoryText == nil && result.categoryTags.isEmpty && result.imageURL == nil)
    }

    @Test func unsafeImageIsIgnoredAndValidFallbackUsed() async throws {
        let (api, session) = service(body: #"{"status":1,"product":{"image_front_url":"file:///private/photo.jpg","image_url":"https://images.openfoodfacts.org/other.jpg"}}"#)
        defer { session.invalidateAndCancel() }
        #expect(try await api.lookup(barcode: "12345678").imageURL?.lastPathComponent == "other.jpg")
    }

    @Test(arguments: ["", "123", "123456789", "abcdefgh", "１２３４５６７８", " 12345678", "1234567/", "123456789012345"])
    func invalidBarcodesNeverMakeRequests(_ barcode: String) async throws {
        let (api, session) = service { _ in Issue.record("Invalid barcode reached the network") }
        defer { session.invalidateAndCancel() }
        await #expect(throws: ProductLookupError.invalidBarcode) { try await api.lookup(barcode: barcode) }
    }

    @Test(arguments: [8, 12, 13, 14])
    func supportedBarcodeLengths(_ length: Int) async throws {
        let (api, session) = service(body: #"{"status":1,"product":{}}"#)
        defer { session.invalidateAndCancel() }
        let barcode = String(repeating: "0", count: length)
        #expect(try await api.lookup(barcode: barcode).barcode == barcode)
    }

    @Test func apiNotFound() async throws {
        let (api, session) = service(body: #"{"status":0,"status_verbose":"product not found"}"#)
        defer { session.invalidateAndCancel() }
        await #expect(throws: ProductLookupError.productNotFound) { try await api.lookup(barcode: "12345678") }
    }

    @Test(arguments: [404, 429, 503, 401])
    func httpErrors(_ status: Int) async throws {
        let (api, session) = service(status: status, body: "not JSON")
        defer { session.invalidateAndCancel() }
        let expected: ProductLookupError = status == 404 ? .productNotFound : status == 429 ? .rateLimited : .httpStatus(status)
        await #expect(throws: expected) { try await api.lookup(barcode: "12345678") }
    }

    @Test(arguments: ["not JSON", "{}", "{\"status\":1}", "{\"status\":2,\"product\":{}}", "{\"status\":1,\"product\":{\"quantity\":42}}"])
    func malformedResponses(_ body: String) async throws {
        let (api, session) = service(body: body)
        defer { session.invalidateAndCancel() }
        await #expect(throws: ProductLookupError.invalidResponse) { try await api.lookup(barcode: "12345678") }
    }

    @Test(arguments: [URLError.Code.timedOut, .notConnectedToInternet, .cannotFindHost])
    func transportErrors(_ code: URLError.Code) async throws {
        let (api, session) = service(error: code)
        defer { session.invalidateAndCancel() }
        let expected: ProductLookupError = code == .timedOut ? .timedOut : .network(code)
        await #expect(throws: expected) { try await api.lookup(barcode: "12345678") }
    }

    @Test func productImageDownloadPreparesJPEG() async throws {
        let (_, session) = service()
        defer { session.invalidateAndCancel() }
        let image = await MainActor.run {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return UIGraphicsImageRenderer(size: CGSize(width: 12, height: 8), format: format).image { context in
                UIColor.green.setFill(); context.fill(CGRect(x: 0, y: 0, width: 12, height: 8))
            }.pngData()!
        }
        ProductHTTPStub.state.set { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "image/png"])!, image)
        }
        let prepared = try await ProductImageLoader(session: session).load(URL(string: "https://images.openfoodfacts.org/test.png")!)
        #expect(prepared.prefix(2) == Data([0xff, 0xd8]))
        #expect(UIImage(data: prepared)?.size.width == 12)
    }

    @Test(arguments: [200, 503])
    func productImageRejectsCorruptionAndHTTPErrors(_ status: Int) async {
        let (_, session) = service(status: status, body: "not an image")
        defer { session.invalidateAndCancel() }
        await #expect(throws: FoodPhotoError.self) {
            try await ProductImageLoader(session: session).load(URL(string: "https://images.openfoodfacts.org/test.jpg")!)
        }
    }

    @Test func cancellationRemainsCancellation() async throws {
        let (api, session) = service(error: .cancelled)
        defer { session.invalidateAndCancel() }
        await #expect(throws: CancellationError.self) { try await api.lookup(barcode: "12345678") }
    }
}

private final class ProductHTTPStub: URLProtocol, @unchecked Sendable {
    static let state = StubState()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (response, data) = try Self.state.respond(to: request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}

    final class StubState: @unchecked Sendable {
        private let lock = NSLock()
        private var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?
        func set(_ handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)) {
            lock.lock(); defer { lock.unlock() }
            self.handler = handler
        }
        func respond(to request: URLRequest) throws -> (HTTPURLResponse, Data) {
            lock.lock()
            let handler = handler
            lock.unlock()
            guard let handler else { throw URLError(.unknown) }
            return try handler(request)
        }
    }
}
