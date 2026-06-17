import Foundation
import SwiftData

/// A single purchased card in the trader's inventory.
///
/// Money is stored as integer minor units (pence/cents) to avoid floating-point
/// drift. Every property has a default and relationships are optional so the model
/// mirrors cleanly to CloudKit.
@Model
final class Card {
    /// Human-friendly unique code shown to the user and encoded in the QR, e.g. "DBF-7K3Q".
    var shortCode: String = ""

    var name: String = ""
    var setName: String = ""
    var cardNumber: String = ""
    var rarity: String = ""
    var conditionRaw: String = CardCondition.nearMint.rawValue

    /// Purchase price in minor currency units (e.g. pence).
    var purchasePriceMinor: Int = 0
    var purchaseDate: Date = Date.distantPast
    var quantity: Int = 1
    var notes: String = ""

    var isSold: Bool = false
    var salePriceMinor: Int = 0
    var soldDate: Date?

    /// Free-form tags the user adds, e.g. "Japanese", "Graded", "For trade".
    var tags: [String] = []

    /// Remote image URL filled in by a card-database lookup (optional).
    var externalImageURL: String = ""

    var createdAt: Date = Date.distantPast

    @Relationship(deleteRule: .nullify, inverse: \GameSystem.cards)
    var gameSystem: GameSystem?

    @Relationship(deleteRule: .cascade, inverse: \CardPhoto.card)
    var photos: [CardPhoto]? = []

    init(
        shortCode: String,
        name: String,
        gameSystem: GameSystem?,
        purchasePriceMinor: Int,
        purchaseDate: Date = Date(),
        quantity: Int = 1
    ) {
        self.shortCode = shortCode
        self.name = name
        self.gameSystem = gameSystem
        self.purchasePriceMinor = purchasePriceMinor
        self.purchaseDate = purchaseDate
        self.quantity = quantity
        self.createdAt = Date()
    }

    // MARK: - Convenience

    var condition: CardCondition {
        get { CardCondition(rawValue: conditionRaw) ?? .nearMint }
        set { conditionRaw = newValue.rawValue }
    }

    /// Purchase price as a `Decimal` in major units.
    var purchasePrice: Decimal {
        get { Decimal(purchasePriceMinor) / 100 }
        set { purchasePriceMinor = NSDecimalNumber(decimal: newValue * 100).intValue }
    }

    var salePrice: Decimal {
        get { Decimal(salePriceMinor) / 100 }
        set { salePriceMinor = NSDecimalNumber(decimal: newValue * 100).intValue }
    }

    /// Photos sorted by their stored order, newest-added last.
    var sortedPhotos: [CardPhoto] {
        (photos ?? []).sorted { $0.sortIndex < $1.sortIndex }
    }
}
