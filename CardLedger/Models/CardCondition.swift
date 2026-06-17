import Foundation

/// Grading scale used across trading-card games. Stored on `Card` as a raw string
/// so it stays CloudKit-friendly and is trivial to extend.
enum CardCondition: String, CaseIterable, Identifiable, Codable {
    case mint = "M"
    case nearMint = "NM"
    case lightlyPlayed = "LP"
    case moderatelyPlayed = "MP"
    case heavilyPlayed = "HP"
    case damaged = "DMG"
    case graded = "GRADED"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .mint: return "Mint"
        case .nearMint: return "Near Mint"
        case .lightlyPlayed: return "Lightly Played"
        case .moderatelyPlayed: return "Moderately Played"
        case .heavilyPlayed: return "Heavily Played"
        case .damaged: return "Damaged"
        case .graded: return "Graded / Slabbed"
        }
    }
}
