import AVFoundation
import CoreData
import ImageIO
import UniformTypeIdentifiers
import SwiftUI
import Testing
@testable import PantryPulse

@MainActor
struct FoodPhotoTests {
    private func picture(_ color: UIColor = .orange, size: CGSize = CGSize(width: 2400, height: 1800)) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return try FoodPhotoStorage.prepare(#require(image.jpegData(compressionQuality: 1)))
    }

    @Test func imagePreparationRejectsCorruptionResizesAndRestrictsDeletion() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = FoodPhotoStorage(root: root)
        #expect(throws: (any Error).self) { try FoodPhotoStorage.prepare(Data("not an image".utf8)) }
        let data = try picture()
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 1600)
        #expect(image.height == 1200)
        let path = try storage.save(data)
        #expect(!path.hasPrefix("/"))
        #expect(try UIImage(data: storage.load(path)) != nil)
        #expect(storage.url(for: "../outside.jpg") == nil)
        #expect(storage.url(for: "/absolute.jpg") == nil)
        let bundled = root.appendingPathComponent("keep.jpg")
        try data.write(to: bundled)
        try storage.remove(bundled.path)
        #expect(FileManager.default.fileExists(atPath: bundled.path))
        let linkPath = "FoodPhotos/\(UUID().uuidString).jpg"
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent(linkPath), withDestinationURL: root.appendingPathComponent(path))
        #expect(storage.url(for: linkPath) == nil)
        try storage.remove(linkPath)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path))
        try storage.remove(path)
        #expect(throws: (any Error).self) { try storage.load(path) }
        let blocker = root.appendingPathComponent("blocker")
        try Data().write(to: blocker)
        #expect(throws: (any Error).self) { try FoodPhotoStorage(root: blocker).save(data) }
    }

    @Test func photoLifecyclePersistsReplacesRemovesCancelsAndProtectsSharedFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let photos = FoodPhotoStorage(root: root)
        let storage = PersistenceController(storeURL: root.appendingPathComponent("pantry.sqlite"))
        await storage.load()
        let container = try #require(storage.container)
        let repo = PantryRepository(container: container, photos: photos)
        let form = AddFoodViewModel(draft: FoodDraft(name: "Photo food"), photos: photos, save: repo.create)
        form.selectPhoto(try picture())
        #expect(form.save())
        let item = try #require(form.savedItem)
        let original = try #require(item.imagePath)
        #expect(try photos.load(original).count > 0)
        let cancelled = AddFoodViewModel(draft: try FoodDraft(item: item), photos: photos, save: repo.update)
        cancelled.selectPhoto(try picture(.blue))
        #expect(try repo.fetch(id: item.id)?.imagePath == original)
        cancelled.removePhoto()
        #expect(try repo.fetch(id: item.id)?.imagePath == original)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(original).path))
        // Failed database writes remove the newly written photo and retain the old one.
        let failed = AddFoodViewModel(draft: try FoodDraft(item: item), photos: photos) { _ in throw PersistenceError.storeUnavailable }
        failed.selectPhoto(try picture(.green))
        #expect(!failed.save())
        #expect(failed.photoData != nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("FoodPhotos").path).count == 1)
        let edit = AddFoodViewModel(draft: try FoodDraft(item: item), photos: photos, save: repo.update)
        edit.selectPhoto(try picture(.green))
        #expect(edit.save())
        let updated = try #require(edit.savedItem)
        let replacement = try #require(updated.imagePath)
        #expect(updated.id == item.id && updated.createdAt == item.createdAt)
        #expect(replacement != original)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(original).path))
        var sharing = FoodDraft(name: "Shared photo")
        sharing.imagePath = replacement
        _ = try repo.create(sharing)
        try repo.delete(id: item.id)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(replacement).path))
        for store in container.persistentStoreCoordinator.persistentStores { try container.persistentStoreCoordinator.remove(store) }
        try photos.markForCleanup(replacement) // A queued referenced file must survive recovery.
        let reopened = PersistenceController(storeURL: root.appendingPathComponent("pantry.sqlite"))
        await reopened.load()
        let newContainer = try #require(reopened.container)
        let newRepo = PantryRepository(container: newContainer, photos: photos)
        let restored = try #require(try newRepo.fetch(id: sharing.id))
        #expect(restored.imagePath == replacement)
        #expect(try photos.load(replacement).count > 0)
        let removal = AddFoodViewModel(draft: try FoodDraft(item: restored), photos: photos, save: newRepo.update)
        removal.removePhoto()
        #expect(removal.save())
        #expect(try newRepo.fetch(id: sharing.id)?.imagePath == nil)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(replacement).path))
        let lastPath = try photos.save(picture())
        var last = FoodDraft(name: "Delete photo")
        last.imagePath = lastPath
        _ = try newRepo.create(last)
        try newRepo.delete(id: last.id)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(lastPath).path))
        for store in newContainer.persistentStoreCoordinator.persistentStores { try newContainer.persistentStoreCoordinator.remove(store) }
    }

    @Test func orientationAndInterruptedWriteRecovery() async throws {
        let data = try picture()
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let cg = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let rotated = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(rotated, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, cg, [kCGImagePropertyOrientation: 6] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        let normalized = try FoodPhotoStorage.prepare(rotated as Data)
        let output = try #require(UIImage(data: normalized)?.cgImage)
        #expect(output.width == 1200 && output.height == 1600)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let photos = FoodPhotoStorage(root: root)
        let abandoned = try photos.save(data)
        let storage = PersistenceController(inMemory: true)
        await storage.load()
        _ = PantryRepository(container: try #require(storage.container), photos: photos)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(abandoned).path))
        #expect(try photos.pendingPaths().isEmpty)
    }

    @Test func cameraAvailabilityAndPermissionDecisions() {
        #expect(FoodCameraAccess.decision(available: false, status: .notDetermined) == .unavailable)
        #expect(FoodCameraAccess.decision(available: true, status: .denied) == .denied)
        #expect(FoodCameraAccess.decision(available: true, status: .restricted) == .denied)
        #expect(FoodCameraAccess.decision(available: true, status: .authorized) == .available)
        #expect(FoodCameraAccess.decision(available: true, status: .notDetermined) == .requestPermission)
    }
}
