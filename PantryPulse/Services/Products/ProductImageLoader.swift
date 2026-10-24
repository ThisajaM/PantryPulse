import Foundation

nonisolated protocol ProductImageLoading: Sendable {
    func load(_ url: URL) async throws -> Data
}

nonisolated struct ProductImageLoader: ProductImageLoading {
    var session: URLSession = .shared
    func load(_ url: URL) async throws -> Data {
        guard url.scheme == "https", url.host != nil else { throw FoodPhotoError.invalidImage }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("PantryPulse/1.0 (https://github.com/ThisajaM/PantryPulse)", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        let limit = 8 * 1024 * 1024
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              response.expectedContentLength <= limit else { throw FoodPhotoError.invalidImage }
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { throw FoodPhotoError.invalidImage }
            data.append(byte)
        }
        try Task.checkCancellation()
        return try await Task.detached { try FoodPhotoStorage.prepare(data) }.value
    }
}
