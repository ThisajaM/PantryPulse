import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Owns only UUID-named JPEGs within Application Support/FoodPhotos.
nonisolated struct FoodPhotoStorage: Sendable {
    let root: URL
    let allowsLegacyPaths: Bool
    init(root: URL = defaultRoot, allowsLegacyPaths: Bool = true) { self.root = root; self.allowsLegacyPaths = allowsLegacyPaths }

    static var defaultRoot: URL {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if let suite = environment["PANTRYPULSE_UI_TEST_DEFAULTS"],
           suite.hasPrefix("PantryPulse.UITests."),
           let id = UUID(uuidString: String(suite.dropFirst("PantryPulse.UITests.".count))) {
            return FileManager.default.temporaryDirectory.appendingPathComponent("UITestPhotos-\(id.uuidString)")
        }
        if environment["XCTestConfigurationFilePath"] != nil || environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return FileManager.default.temporaryDirectory.appendingPathComponent("TestPhotos-\(ProcessInfo.processInfo.processIdentifier)")
        }
        #endif
        return URL.applicationSupportDirectory
    }

    static func prepare(_ data: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 1600,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw FoodPhotoError.invalidImage }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw FoodPhotoError.invalidImage
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw FoodPhotoError.invalidImage }
        return output as Data
    }

    func save(_ preparedData: Data) throws -> String {
        let path = "FoodPhotos/\(UUID().uuidString).jpg"
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try markForCleanup(path)
        guard let safeURL = self.url(for: path) else { throw FoodPhotoError.invalidImage }
        try preparedData.write(to: safeURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return path
    }

    func url(for path: String) -> URL? {
        guard isManaged(path) else { return nil }
        let base = root.standardizedFileURL.resolvingSymlinksInPath()
        let url = base.appendingPathComponent(path).standardizedFileURL.resolvingSymlinksInPath()
        guard url.path == base.appendingPathComponent(path).path else { return nil }
        return url
    }

    func remove(_ path: String) throws {
        guard let url = url(for: path) else { return }
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        try finishCleanup(path)
    }

    // A small durable journal lets the repository recover interrupted writes and retry cleanup.
    private var journal: URL { root.appendingPathComponent("FoodPhotoCleanup.json") }
    func pendingPaths() throws -> Set<String> {
        guard FileManager.default.fileExists(atPath: journal.path) else { return [] }
        return Set(try JSONDecoder().decode([String].self, from: Data(contentsOf: journal)).filter(isManaged))
    }
    func markForCleanup(_ path: String) throws {
        guard isManaged(path) else { return }
        var paths = try pendingPaths()
        paths.insert(path)
        try writeJournal(paths)
    }
    func finishCleanup(_ path: String) throws {
        var paths = try pendingPaths()
        guard paths.remove(path) != nil else { return }
        try writeJournal(paths)
    }
    private func writeJournal(_ paths: Set<String>) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(paths.sorted()).write(to: journal, options: .atomic)
    }

    func load(_ path: String) throws -> Data {
        let sourceURL: URL
        if let managed = url(for: path) {
            sourceURL = managed
        } else {
            // Read-only compatibility with earlier app-owned paths. Never delete these files.
            let home = URL(fileURLWithPath: NSHomeDirectory()).resolvingSymlinksInPath()
            guard allowsLegacyPaths else { throw FoodPhotoError.invalidImage }
            let legacy = (path.hasPrefix("/") ? URL(fileURLWithPath: path) : home.appendingPathComponent(path))
                .standardizedFileURL.resolvingSymlinksInPath()
            guard legacy.path.hasPrefix(home.path + "/") else { throw FoodPhotoError.invalidImage }
            sourceURL = legacy
        }
        return try Self.prepare(Data(contentsOf: sourceURL, options: .mappedIfSafe))
    }

    private func isManaged(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0] == "FoodPhotos", parts[1].hasSuffix(".jpg") else { return false }
        return UUID(uuidString: String(parts[1].dropLast(4))) != nil
    }
}

nonisolated enum FoodPhotoError: LocalizedError {
    case invalidImage
    var errorDescription: String? { "This photo could not be opened. Please choose another image." }
}
