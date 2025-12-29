import Foundation
import SwiftData

@Model
final class ItemKnowledge {
    @Attribute(.unique) var normalizedName: String
    var categoryDefaultRaw: String
    var storageAdvice: String?
    var shelfLifeDaysMin: Int?
    var shelfLifeDaysMax: Int?
    var source: String
    var updatedAt: Date

    init(
        normalizedName: String,
        categoryDefault: GroceryCategory = .other,
        storageAdvice: String? = nil,
        shelfLifeDaysMin: Int? = nil,
        shelfLifeDaysMax: Int? = nil,
        source: String = "Seed",
        updatedAt: Date = Date()
    ) {
        self.normalizedName = normalizedName
        self.categoryDefaultRaw = categoryDefault.rawValue
        self.storageAdvice = storageAdvice
        self.shelfLifeDaysMin = shelfLifeDaysMin
        self.shelfLifeDaysMax = shelfLifeDaysMax
        self.source = source
        self.updatedAt = updatedAt
    }

    var categoryDefault: GroceryCategory {
        get {
            GroceryCategory(rawValue: categoryDefaultRaw) ?? .other
        }
        set {
            categoryDefaultRaw = newValue.rawValue
        }
    }
}
