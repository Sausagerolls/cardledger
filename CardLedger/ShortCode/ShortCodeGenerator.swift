import Foundation
import SwiftData

/// Generates short, human-readable, unambiguous codes for cards, e.g. "DBF-7K3Q".
///
/// Uses Crockford base32 (no I, L, O, U) so codes are easy to read aloud and type.
enum ShortCodeGenerator {
    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    /// Build a code with the game prefix and a random suffix of `length` chars.
    static func make(prefix: String, length: Int = 4) -> String {
        let suffix = (0..<length).map { _ in alphabet.randomElement()! }
        let clean = prefix.isEmpty ? "GEN" : prefix.uppercased()
        return "\(clean)-\(String(suffix))"
    }

    /// Generate a code guaranteed not to collide with existing cards in `context`.
    static func makeUnique(prefix: String, in context: ModelContext) -> String {
        for _ in 0..<12 {
            let candidate = make(prefix: prefix)
            var descriptor = FetchDescriptor<Card>(predicate: #Predicate { $0.shortCode == candidate })
            descriptor.fetchLimit = 1
            let existing = (try? context.fetch(descriptor)) ?? []
            if existing.isEmpty { return candidate }
        }
        // Astronomically unlikely fallback: widen the suffix.
        return make(prefix: prefix, length: 6)
    }
}
