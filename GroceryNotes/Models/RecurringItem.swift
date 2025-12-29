import Foundation
import SwiftData

enum RecurringSeasonality: String, Codable, CaseIterable {
    case allYear = "All Year"
    case spring = "Spring"
    case summer = "Summer"
    case fall = "Fall"
    case winter = "Winter"
}

@Model
final class RecurringItem {
    var normalizedName: String
    var displayName: String
    var defaultCategoryRaw: String
    var defaultQuantity: String?
    var storageAdvice: String?
    var shelfLifeDaysMin: Int?
    var shelfLifeDaysMax: Int?
    var source: String
    var updatedAt: Date
    var userOverride: Bool
    var seasonalityRaw: String

    init(
        normalizedName: String,
        displayName: String,
        defaultCategory: GroceryCategory = .other,
        defaultQuantity: String? = nil,
        storageAdvice: String? = nil,
        shelfLifeDaysMin: Int? = nil,
        shelfLifeDaysMax: Int? = nil,
        source: String = "User",
        updatedAt: Date = Date(),
        userOverride: Bool = false,
        seasonality: RecurringSeasonality = .allYear
    ) {
        self.normalizedName = normalizedName
        self.displayName = displayName
        self.defaultCategoryRaw = defaultCategory.rawValue
        self.defaultQuantity = defaultQuantity
        self.storageAdvice = storageAdvice
        self.shelfLifeDaysMin = shelfLifeDaysMin
        self.shelfLifeDaysMax = shelfLifeDaysMax
        self.source = source
        self.updatedAt = updatedAt
        self.userOverride = userOverride
        self.seasonalityRaw = seasonality.rawValue
    }

    var defaultCategory: GroceryCategory {
        get {
            GroceryCategory(rawValue: defaultCategoryRaw) ?? .other
        }
        set {
            defaultCategoryRaw = newValue.rawValue
        }
    }

    var seasonality: RecurringSeasonality {
        get {
            RecurringSeasonality(rawValue: seasonalityRaw) ?? .allYear
        }
        set {
            seasonalityRaw = newValue.rawValue
        }
    }
}
