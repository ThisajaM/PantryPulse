import FirebaseAuth
import FirebaseFirestore
import Foundation

/// Explicit cloud copies only. This service never writes to Core Data or uploads local photos.
@MainActor
final class CloudPantryService {
    private let auth: Auth
    private let database: Firestore
    init(auth: Auth = Auth.auth(), database: Firestore = Firestore.firestore()) {
        self.auth = auth
        self.database = database
    }

    /// Creates once, or accepts an identical retry. A different snapshot requires conflict resolution.
    func createSnapshot(_ item: PantryItem) async throws {
        let owner = try currentOwner()
        let payload = try CloudPantryDocument(item: item, ownerID: owner)
        let reference = database.collection("users").document(owner).collection("pantry").document(item.id.uuidString)
        let values = try Firestore.Encoder().encode(payload)
        _ = try await database.runTransaction { transaction, error in
            do {
                let existing = try transaction.getDocument(reference)
                if existing.exists {
                    let stored = try existing.data(as: CloudPantryDocument.self)
                    guard stored == payload else { throw CloudPantryError.conflict }
                } else {
                    var data = values
                    data["uploadedAt"] = FieldValue.serverTimestamp()
                    transaction.setData(data, forDocument: reference)
                }
                return nil
            } catch let failure {
                error?.pointee = failure as NSError
                return nil
            }
        }
        guard auth.currentUser?.uid == owner else { throw CloudPantryError.sessionChanged }
    }

    /// Server-only reads never substitute another user's cached data or offline success.
    func fetchSnapshot(id: UUID) async throws -> CloudPantryDocument? {
        let owner = try currentOwner()
        let snapshot = try await database.collection("users").document(owner)
            .collection("pantry").document(id.uuidString).getDocument(source: .server)
        guard auth.currentUser?.uid == owner else { throw CloudPantryError.sessionChanged }
        guard snapshot.exists else { return nil }
        let document = try snapshot.data(as: CloudPantryDocument.self)
        guard document.ownerID == owner, document.id == id.uuidString else { throw CloudPantryError.invalidDocument }
        return document
    }

    private func currentOwner() throws -> String {
        guard let user = auth.currentUser, !user.isAnonymous else { throw CloudPantryError.signInRequired }
        return user.uid
    }
}

enum CloudPantryError: LocalizedError {
    case signInRequired, sessionChanged, conflict, invalidDocument
    var errorDescription: String? {
        switch self {
        case .signInRequired: "Sign in before accessing cloud pantry records."
        case .sessionChanged: "Your account changed during the request. A completed write may exist in the original account; no local data was changed."
        case .conflict: "A different cloud copy already exists for this food. Nothing was overwritten."
        case .invalidDocument: "The cloud food record is incomplete or invalid."
        }
    }
}
