import Foundation
import SwiftData

@Model
final class GroceryItem {
    var id: UUID
    var name: String
    var normalizedName: String
    var quantity: String?
    var categoryRaw: String
    var isChecked: Bool
    var checkedAt: Date?
    var isRecurring: Bool
    var createdAt: Date
    var updatedAt: Date

    var storageAdvice: String?
    var shelfLifeDaysMin: Int?
    var shelfLifeDaysMax: Int?
    var shelfLifeSource: String?
    var purchasedAt: Date?
    var estimatedBestBy: Date?

    // Author tracking for shared lists
    var createdByUserId: String?
    var createdByName: String?

    // Image override properties (Phase 2)
    var customImageName: String?
    var customImageURL: String?

    var note: GroceryNote?

    init(
        id: UUID = UUID(),
        name: String,
        normalizedName: String? = nil,
        quantity: String? = nil,
        category: GroceryCategory = .other,
        isChecked: Bool = false,
        checkedAt: Date? = nil,
        isRecurring: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        storageAdvice: String? = nil,
        shelfLifeDaysMin: Int? = nil,
        shelfLifeDaysMax: Int? = nil,
        shelfLifeSource: String? = nil,
        purchasedAt: Date? = nil,
        estimatedBestBy: Date? = nil,
        createdByUserId: String? = nil,
        createdByName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.normalizedName = normalizedName ?? name.lowercased().trimmingCharacters(in: .whitespaces)
        self.quantity = quantity
        self.categoryRaw = category.rawValue
        self.isChecked = isChecked
        self.checkedAt = checkedAt
        self.isRecurring = isRecurring
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.storageAdvice = storageAdvice
        self.shelfLifeDaysMin = shelfLifeDaysMin
        self.shelfLifeDaysMax = shelfLifeDaysMax
        self.shelfLifeSource = shelfLifeSource
        self.purchasedAt = purchasedAt
        self.estimatedBestBy = estimatedBestBy
        self.createdByUserId = createdByUserId
        self.createdByName = createdByName
    }

    var category: GroceryCategory {
        get {
            GroceryCategory(rawValue: categoryRaw) ?? .other
        }
        set {
            categoryRaw = newValue.rawValue
        }
    }

    var displayImageName: String? {
        // Priority 1: Custom asset name (if explicitly set)
        if let imageName = customImageName {
            return imageName
        }
        // Priority 2: Try normalized name (handles plurals smartly)
        // Check exact match first, then try removing 's' for plurals
        let normalized = normalizedName.lowercased()

        // Try exact match first
        return normalized
    }

    func toggleCheck() {
        isChecked.toggle()
        checkedAt = isChecked ? Date() : nil
        updatedAt = Date()
    }

    func toggleRecurring() {
        isRecurring.toggle()
        updatedAt = Date()
    }

    var shelfLifeDescription: String? {
        guard let min = shelfLifeDaysMin, let max = shelfLifeDaysMax else {
            return nil
        }
        if min == max {
            return "\(min) days"
        }
        return "\(min)-\(max) days"
    }

    var emoji: String {
        // Use ItemEmojiMapper for centralized emoji lookup
        let mapper = ItemEmojiMapper()
        return ItemEmojiMapper.emoji(for: normalizedName, category: category)
    }
}
