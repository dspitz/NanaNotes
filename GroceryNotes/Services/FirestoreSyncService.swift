import Foundation
import FirebaseFirestore
import SwiftData

@Observable
class FirestoreSyncService {
    static let shared = FirestoreSyncService()

    private let db = Firestore.firestore()
    private var listeners: [ListenerRegistration] = []

    private init() {
        // Configure Firestore settings with cache
        let settings = FirestoreSettings()
        settings.cacheSettings = PersistentCacheSettings()
        db.settings = settings
    }

    // MARK: - List Management

    func createList(title: String, userId: String) async throws -> String {
        let listData: [String: Any] = [
            "title": title,
            "ownerId": userId,
            "createdAt": Timestamp(date: Date()),
            "updatedAt": Timestamp(date: Date()),
            "isCompleted": false,
            "members": [userId: "owner"]
        ]

        let docRef = try await db.collection("lists").addDocument(data: listData)
        return docRef.documentID
    }

    func updateList(listId: String, title: String) async throws {
        try await db.collection("lists").document(listId).updateData([
            "title": title,
            "updatedAt": Timestamp(date: Date())
        ])
    }

    func deleteList(listId: String) async throws {
        // Delete all items in the list first
        let itemsSnapshot = try await db.collection("lists").document(listId).collection("items").getDocuments()
        for doc in itemsSnapshot.documents {
            try await doc.reference.delete()
        }

        // Delete the list
        try await db.collection("lists").document(listId).delete()
    }

    func markListCompleted(listId: String, completed: Bool) async throws {
        try await db.collection("lists").document(listId).updateData([
            "isCompleted": completed,
            "completedAt": completed ? Timestamp(date: Date()) : FieldValue.delete(),
            "updatedAt": Timestamp(date: Date())
        ])
    }

    // MARK: - Item Management

    func addItem(listId: String, name: String, emoji: String, category: String, quantity: String?, isRecurring: Bool) async throws -> String {
        let itemData: [String: Any] = [
            "name": name,
            "emoji": emoji,
            "category": category,
            "quantity": quantity as Any,
            "isChecked": false,
            "isRecurring": isRecurring,
            "createdAt": Timestamp(date: Date()),
            "updatedAt": Timestamp(date: Date())
        ]

        let docRef = try await db.collection("lists").document(listId).collection("items").addDocument(data: itemData)
        return docRef.documentID
    }

    func updateItem(listId: String, itemId: String, updates: [String: Any]) async throws {
        var data = updates
        data["updatedAt"] = Timestamp(date: Date())

        try await db.collection("lists").document(listId).collection("items").document(itemId).updateData(data)
    }

    func deleteItem(listId: String, itemId: String) async throws {
        try await db.collection("lists").document(listId).collection("items").document(itemId).delete()
    }

    func toggleItemCheck(listId: String, itemId: String, isChecked: Bool) async throws {
        try await db.collection("lists").document(listId).collection("items").document(itemId).updateData([
            "isChecked": isChecked,
            "updatedAt": Timestamp(date: Date())
        ])
    }

    // MARK: - Sharing

    func shareList(listId: String, withEmail: String, role: String = "editor") async throws {
        // In production, you'd look up the user by email first
        // For now, we'll create an invite
        let inviteData: [String: Any] = [
            "listId": listId,
            "email": withEmail,
            "role": role,
            "createdAt": Timestamp(date: Date()),
            "status": "pending"
        ]

        try await db.collection("invites").addDocument(data: inviteData)
    }

    func addMemberToList(listId: String, userId: String, role: String = "editor") async throws {
        try await db.collection("lists").document(listId).updateData([
            "members.\(userId)": role,
            "updatedAt": Timestamp(date: Date())
        ])
    }

    func removeMemberFromList(listId: String, userId: String) async throws {
        try await db.collection("lists").document(listId).updateData([
            "members.\(userId)": FieldValue.delete(),
            "updatedAt": Timestamp(date: Date())
        ])
    }

    func generateShareCode(listId: String) async throws -> String {
        let code = String(format: "%06d", Int.random(in: 100000...999999))

        let shareCodeData: [String: Any] = [
            "listId": listId,
            "code": code,
            "createdAt": Timestamp(date: Date()),
            "expiresAt": Timestamp(date: Date().addingTimeInterval(24 * 60 * 60)) // 24 hours
        ]

        try await db.collection("shareCodes").document(code).setData(shareCodeData)
        return code
    }

    func joinListWithCode(code: String, userId: String) async throws -> String {
        let doc = try await db.collection("shareCodes").document(code).getDocument()

        guard let data = doc.data(),
              let listId = data["listId"] as? String,
              let expiresAt = (data["expiresAt"] as? Timestamp)?.dateValue() else {
            throw SyncError.invalidShareCode
        }

        guard expiresAt > Date() else {
            throw SyncError.expiredShareCode
        }

        try await addMemberToList(listId: listId, userId: userId, role: "editor")
        return listId
    }

    // MARK: - Real-time Listeners

    func listenToLists(userId: String, onChange: @escaping ([FirestoreList]) -> Void) -> ListenerRegistration {
        let listener = db.collection("lists")
            .whereField("members.\(userId)", isNotEqualTo: NSNull())
            .order(by: "updatedAt", descending: true)
            .addSnapshotListener { snapshot, error in
                guard let documents = snapshot?.documents else { return }

                let lists = documents.compactMap { doc -> FirestoreList? in
                    try? doc.data(as: FirestoreList.self)
                }

                onChange(lists)
            }

        listeners.append(listener)
        return listener
    }

    func listenToListItems(listId: String, onChange: @escaping ([FirestoreItem]) -> Void) -> ListenerRegistration {
        let listener = db.collection("lists").document(listId).collection("items")
            .order(by: "createdAt")
            .addSnapshotListener { snapshot, error in
                guard let documents = snapshot?.documents else { return }

                let items = documents.compactMap { doc -> FirestoreItem? in
                    try? doc.data(as: FirestoreItem.self)
                }

                onChange(items)
            }

        listeners.append(listener)
        return listener
    }

    func removeAllListeners() {
        listeners.forEach { $0.remove() }
        listeners.removeAll()
    }
}

// MARK: - Firebase Models

struct FirestoreList: Codable, Identifiable {
    @DocumentID var id: String?
    var title: String
    var ownerId: String
    var members: [String: String] // userId: role
    var createdAt: Timestamp
    var updatedAt: Timestamp
    var isCompleted: Bool
    var completedAt: Timestamp?
}

struct FirestoreItem: Codable, Identifiable {
    @DocumentID var id: String?
    var name: String
    var emoji: String
    var category: String
    var quantity: String?
    var isChecked: Bool
    var isRecurring: Bool
    var createdAt: Timestamp
    var updatedAt: Timestamp
}

enum SyncError: LocalizedError {
    case invalidShareCode
    case expiredShareCode

    var errorDescription: String? {
        switch self {
        case .invalidShareCode:
            return "Invalid share code"
        case .expiredShareCode:
            return "Share code has expired"
        }
    }
}
