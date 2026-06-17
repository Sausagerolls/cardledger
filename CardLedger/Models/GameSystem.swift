import Foundation
import SwiftData

/// A trading-card game system (e.g. Dragon Ball Fusion World). Kept as a model
/// rather than an enum so the user can add their own systems over time.
///
/// All properties have defaults and the relationship is optional — required for
/// SwiftData's CloudKit mirroring.
@Model
final class GameSystem {
    var name: String = ""
    /// Short prefix used in card short codes, e.g. "DBF".
    var code: String = ""
    /// SF Symbol name shown in lists.
    var iconSymbol: String = "rectangle.stack"
    var sortIndex: Int = 0
    var createdAt: Date = Date.distantPast

    @Relationship(deleteRule: .nullify)
    var cards: [Card]? = []

    init(name: String, code: String, iconSymbol: String = "rectangle.stack", sortIndex: Int = 0) {
        self.name = name
        self.code = code.uppercased()
        self.iconSymbol = iconSymbol
        self.sortIndex = sortIndex
        self.createdAt = Date()
    }

    /// Game systems seeded on first launch. Dragon Ball first, others to show
    /// the app is multi-system from day one.
    static let seeds: [(name: String, code: String, icon: String)] = [
        ("Dragon Ball Fusion World", "DBF", "bolt.circle"),
        ("Dragon Ball Super CG", "DBS", "bolt.circle.fill"),
        ("Pokémon TCG", "PKM", "circle.hexagongrid"),
        ("Magic: The Gathering", "MTG", "wand.and.stars"),
        ("Yu-Gi-Oh!", "YGO", "pyramid"),
        ("One Piece CG", "OPC", "sailboat"),
        ("Other / Custom", "GEN", "square.stack.3d.up")
    ]
}
