import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import Foundation
import Testing
@testable import PantryPulse

@MainActor
struct CloudPantryTests {
    static func item() -> PantryItem {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return PantryItem(id: UUID(), name: "Cloud test food", storageLocation: "Pantry", addedAt: now,
                          quantity: 2, quantityUnit: .pieces, purchaseDate: now,
                          imagePath: "FoodPhotos/local-only.jpg", updatedAt: now)
    }

    @Test func preservesIdentifiersDatesAndDoesNotSerializeLocalPhotos() throws {
        let item = Self.item()
        let document = try CloudPantryDocument(item: item, ownerID: "owner")
        let fields = try Firestore.Encoder().encode(document)
        #expect(document.id == item.id.uuidString)
        #expect(document.createdAt == item.createdAt)
        #expect(document.expiryDate == nil)
        #expect(fields["imagePath"] == nil)
        #expect(item.imagePath == "FoodPhotos/local-only.jpg")
        #expect(try CloudPantryDocument(item: item, ownerID: "owner") == document)
    }

    @Test func rejectsIncompleteSnapshots() throws {
        var item = Self.item()
        item.quantity = .nan
        #expect(throws: (any Error).self) { try CloudPantryDocument(item: item, ownerID: "owner") }
        item = Self.item()
        item.updatedAt = nil
        #expect(throws: (any Error).self) { try CloudPantryDocument(item: item, ownerID: "owner") }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["PANTRYPULSE_FIRESTORE_EMULATOR"] == "1"))
    func realSDKEmulatorRoundTripRetryConflictAndSignOut() async throws {
        let options = FirebaseOptions(googleAppID: "1:123456789:ios:abcdef123456", gcmSenderID: "123456789")
        options.projectID = "demo-pantrypulse"
        // Satisfies SDK format validation; this is not a real API credential.
        options.apiKey = "A" + String(repeating: "0", count: 38)
        FirebaseApp.configure(name: "CloudEmulatorTests", options: options)
        let app = try #require(FirebaseApp.app(name: "CloudEmulatorTests"))
        let auth = Auth.auth(app: app)
        auth.useEmulator(withHost: "127.0.0.1", port: 9099)
        let database = Firestore.firestore(app: app)
        let settings = database.settings
        settings.host = "127.0.0.1:8080"
        settings.isSSLEnabled = false
        settings.cacheSettings = MemoryCacheSettings()
        database.settings = settings
        let ownerEmail = "test-\(UUID())@example.invalid"
        let ownerPassword = UUID().uuidString
        let owner = try await auth.createUser(withEmail: ownerEmail, password: ownerPassword).user.uid
        let service = CloudPantryService(auth: auth, database: database)
        var item = Self.item()
        try await service.createSnapshot(item)
        let read = try #require(try await service.fetchSnapshot(id: item.id))
        #expect(read.name == item.name)
        #expect(read.ownerID == auth.currentUser?.uid)
        try await service.createSnapshot(item)
        item.name = "Changed food"
        do { try await service.createSnapshot(item); Issue.record("Conflicting snapshot was overwritten") }
        catch {
            let expected = CloudPantryError.conflict as NSError
            #expect((error as NSError).domain == expected.domain)
            #expect((error as NSError).code == expected.code)
            #expect((try await service.fetchSnapshot(id: item.id))?.name == "Cloud test food")
        }
        try auth.signOut()
        _ = try await auth.createUser(withEmail: "other-\(UUID())@example.invalid", password: UUID().uuidString)
        #expect(try await service.fetchSnapshot(id: item.id) == nil)
        let protected = database.collection("users").document(owner).collection("pantry").document(item.id.uuidString)
        do { _ = try await protected.getDocument(source: .server); Issue.record("Cross-account read accepted") }
        catch { #expect((error as NSError).code == FirestoreErrorCode.permissionDenied.rawValue) }
        do { try await protected.setData(["name": "Unauthorized"]); Issue.record("Cross-account write accepted") }
        catch { #expect((error as NSError).code == FirestoreErrorCode.permissionDenied.rawValue) }
        try auth.signOut()
        _ = try await auth.signIn(withEmail: ownerEmail, password: ownerPassword)
        #expect((try await service.fetchSnapshot(id: item.id))?.name == "Cloud test food")
        try auth.signOut()
        do { _ = try await service.fetchSnapshot(id: item.id); Issue.record("Signed-out request accepted") }
        catch { #expect(error is CloudPantryError) }
    }
}
