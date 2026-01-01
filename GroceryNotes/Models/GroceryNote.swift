import Foundation
import SwiftData

@Model
final class GroceryNote {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?
    var storeProfileId: String?
    var shareMetadata: Data?
    var firebaseListId: String?

    @Relationship(deleteRule: .cascade, inverse: \GroceryItem.note)
    var items: [GroceryItem]

    init(
        id: UUID = UUID(),
        title: String = "Grocery Run",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        completedAt: Date? = nil,
        storeProfileId: String? = nil,
        shareMetadata: Data? = nil,
        firebaseListId: String? = nil,
        items: [GroceryItem] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.storeProfileId = storeProfileId
        self.shareMetadata = shareMetadata
        self.firebaseListId = firebaseListId
        self.items = items
    }

    var isCompleted: Bool {
        completedAt != nil
    }

    var progress: (checked: Int, total: Int) {
        let checked = items.filter { $0.isChecked }.count
        return (checked, items.count)
    }

    func markComplete() {
        completedAt = Date()
        updatedAt = Date()

        for item in items where item.isChecked {
            item.purchasedAt = completedAt
            if let shelfMin = item.shelfLifeDaysMin, let shelfMax = item.shelfLifeDaysMax {
                let avgShelfLife = (shelfMin + shelfMax) / 2
                item.estimatedBestBy = Calendar.current.date(byAdding: .day, value: avgShelfLife, to: completedAt!)
            }
        }
    }

    func checkIfShouldUncomplete() {
        if completedAt != nil && items.contains(where: { !$0.isChecked }) {
            completedAt = nil
            updatedAt = Date()
        }
    }
}
