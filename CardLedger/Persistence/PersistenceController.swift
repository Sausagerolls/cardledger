import Foundation
import SwiftData

/// Builds the SwiftData `ModelContainer`.
///
/// iCloud backup: when the app is signed with an Apple Developer team that has the
/// iCloud/CloudKit capability + the entitlement (see `Support/CardLedger.entitlements`
/// and README), SwiftData mirrors the store to the user's private CloudKit database
/// automatically — photos included, since they use external storage.
///
/// We *try* a CloudKit-backed container first and fall back to a local-only store if
/// the entitlement isn't present (e.g. running in the Simulator unsigned). That keeps
/// the app runnable everywhere while giving real iCloud sync on a properly-signed build.
enum PersistenceController {
    static let schema = Schema([Card.self, CardPhoto.self, GameSystem.self])

    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        if inMemory {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: config)
        }

        // The user's iCloud preference (default on). Read here so this stays free of any
        // SettingsStore dependency; changing it applies at the next launch.
        let useCloud = UserDefaults.standard.object(forKey: SettingsStore.iCloudSyncKey) as? Bool ?? true

        if useCloud {
            // Preferred: CloudKit-mirrored store (real iCloud backup).
            do {
                let cloud = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
                return try ModelContainer(for: schema, configurations: cloud)
            } catch {
                #if DEBUG
                print("⚠️ CloudKit container unavailable, using local store: \(error.localizedDescription)")
                #endif
            }
        }
        // Local-only store (user disabled iCloud, or CloudKit unavailable in the Simulator).
        let local = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        return try! ModelContainer(for: schema, configurations: local)
    }

    /// Seed the default game systems once, if none exist yet.
    @MainActor
    static func seedIfNeeded(_ context: ModelContext) {
        var descriptor = FetchDescriptor<GameSystem>()
        descriptor.fetchLimit = 1
        let existing = (try? context.fetch(descriptor)) ?? []
        guard existing.isEmpty else { return }

        for (index, seed) in GameSystem.seeds.enumerated() {
            let system = GameSystem(name: seed.name, code: seed.code, iconSymbol: seed.icon, sortIndex: index)
            context.insert(system)
        }
        try? context.save()
    }

    #if DEBUG
    /// Insert a few demo cards (idempotent) for screenshots / UI tours.
    @MainActor
    static func seedSampleCards(_ context: ModelContext) {
        var check = FetchDescriptor<Card>()
        check.fetchLimit = 1
        if let existing = try? context.fetch(check), !existing.isEmpty { return }

        let systems = (try? context.fetch(FetchDescriptor<GameSystem>())) ?? []
        let dbf = systems.first { $0.code == "DBF" }

        let samples: [(String, String, String, Int, CardCondition)] = [
            ("Son Goku", "Awakened Pulse", "FB01-001", 4500, .nearMint),
            ("Vegeta", "Awakened Pulse", "FB01-026", 1200, .lightlyPlayed),
            ("Frieza, Galactic Tyrant", "Blazing Aura", "FB02-114", 8000, .graded),
            ("Piccolo", "Blazing Aura", "FB02-040", 350, .nearMint)
        ]
        for (i, s) in samples.enumerated() {
            let card = Card(shortCode: ShortCodeGenerator.makeUnique(prefix: "DBF", in: context),
                            name: s.0, gameSystem: dbf, purchasePriceMinor: s.3,
                            purchaseDate: Date(), quantity: i == 1 ? 3 : 1)
            card.setName = s.1; card.cardNumber = s.2; card.condition = s.4
            card.rarity = i == 2 ? "Secret Rare" : "Super Rare"
            card.tags = i == 2 ? ["Japanese", "Graded"] : ["English"]
            context.insert(card)
        }
        try? context.save()
    }
    #endif
}
