import Foundation

/// One result row returned by a card-database lookup.
struct CardLookupResult: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var setName: String
    var number: String
    var rarity: String
    var imageURL: String
}

/// Which field the user is searching the card database by.
enum CardSearchField: String, CaseIterable, Identifiable {
    case name
    case number
    var id: String { rawValue }
    var label: String { self == .name ? "Name" : "Number" }
    var prompt: String { self == .name ? "Card name" : "Card number (e.g. FB01-001)" }
}

/// A pluggable source of card metadata for a given game system. Add a conformer and
/// register it in `CardDatabaseRegistry` to support another game — each game can use a
/// completely different backend.
protocol CardDatabaseProvider {
    /// Game system code this provider serves, e.g. "DBF".
    var gameCode: String { get }
    /// Human label for the source, shown in the UI ("Powered by …").
    var sourceName: String { get }
    /// Whether this provider needs the user's API key from Settings.
    var requiresAPIKey: Bool { get }
    /// Whether searching by card number is supported by this source.
    var supportsNumberSearch: Bool { get }
    func search(_ query: String, field: CardSearchField, apiKey: String) async throws -> [CardLookupResult]
}

extension CardDatabaseProvider {
    var requiresAPIKey: Bool { false }
    var supportsNumberSearch: Bool { true }
}

enum CardDatabaseError: LocalizedError {
    case missingAPIKey
    case badResponse
    case notSupported

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "Add this game's API key in Settings to enable auto-fill."
        case .badResponse: return "The card database returned an unexpected response. Try again."
        case .notSupported: return "Auto-fill isn't available for this game yet — enter details manually."
        }
    }
}

/// Maps a game code to its provider. Returns `nil` (manual entry) when none is registered.
enum CardDatabaseRegistry {
    private static let providers: [CardDatabaseProvider] = [
        DragonBallFusionProvider(),
        ScryfallProvider(),
        YGOPRODeckProvider(),
        PokemonTCGProvider()
    ]

    static func provider(for gameCode: String) -> CardDatabaseProvider? {
        providers.first { $0.gameCode == gameCode.uppercased() }
    }
}

// MARK: - Dragon Ball Fusion World (static dataset, no key)

/// Loads the community-maintained Dragon Ball Fusion World dataset (official Bandai art)
/// straight from GitHub raw — no API key, no rate limit. Cards are cached for the session
/// and filtered locally, so searches after the first are instant.
struct DragonBallFusionProvider: CardDatabaseProvider {
    let gameCode = "DBF"
    let sourceName = "Bandai card list (dbs-cardgame.com)"

    func search(_ query: String, field: CardSearchField, apiKey: String) async throws -> [CardLookupResult] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let all = try await DBFusionCache.shared.all()
        guard !q.isEmpty else { return Array(all.prefix(40)) }
        let matches: [CardLookupResult]
        switch field {
        case .name:   matches = all.filter { $0.name.lowercased().contains(q) }
        case .number: matches = all.filter { $0.number.lowercased().contains(q) }
        }
        return Array(matches.prefix(60))
    }
}

/// Session cache + loader for the Dragon Ball dataset.
actor DBFusionCache {
    static let shared = DBFusionCache()
    private var cached: [CardLookupResult]?

    // Known set files in the dataset. New sets => bump this list (or app update).
    private let setFiles = [
        "fb01", "fb02", "fb03", "fb04", "fb05", "fb06",
        "fs01", "fs02", "fs03", "fs04", "fs05", "fs06", "fs07", "fs08", "fs09", "fs10",
        "sb01", "promotion"
    ]
    private let base = "https://raw.githubusercontent.com/apitcg/dragon-ball-fusion-tcg-data/main/cards/en"

    func all() async throws -> [CardLookupResult] {
        if let cached { return cached }
        var results: [CardLookupResult] = []
        try await withThrowingTaskGroup(of: [CardLookupResult].self) { group in
            for file in setFiles {
                group.addTask { await Self.loadFile(file, base: self.base) }
            }
            for try await batch in group { results.append(contentsOf: batch) }
        }
        guard !results.isEmpty else { throw CardDatabaseError.badResponse }
        cached = results
        return results
    }

    private static func loadFile(_ file: String, base: String) async -> [CardLookupResult] {
        guard let url = URL(string: "\(base)/\(file).json") else { return [] }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let cards = try? JSONDecoder().decode([DBFCard].self, from: data) else { return [] }
        return cards.map {
            CardLookupResult(
                name: $0.name ?? "",
                setName: $0.set?.name?.capitalized ?? "",
                number: $0.code ?? $0.id ?? "",
                rarity: $0.rarity ?? "",
                imageURL: $0.images?.large ?? $0.images?.small ?? ""
            )
        }
    }

    private struct DBFCard: Decodable {
        let id: String?
        let code: String?
        let name: String?
        let rarity: String?
        let images: Imgs?
        let set: SetInfo?
        struct Imgs: Decodable { let small: String?; let large: String? }
        struct SetInfo: Decodable { let name: String? }
    }
}

// MARK: - Magic: The Gathering (Scryfall, no key)

struct ScryfallProvider: CardDatabaseProvider {
    let gameCode = "MTG"
    let sourceName = "Scryfall"

    func search(_ query: String, field: CardSearchField, apiKey: String) async throws -> [CardLookupResult] {
        guard var c = URLComponents(string: "https://api.scryfall.com/cards/search") else { throw CardDatabaseError.badResponse }
        // Scryfall query syntax: collector number is `cn:`.
        let scryQuery = field == .number ? "cn:\(query)" : query
        c.queryItems = [URLQueryItem(name: "q", value: scryQuery), URLQueryItem(name: "order", value: "name")]
        guard let url = c.url else { throw CardDatabaseError.badResponse }
        let (data, response) = try await URLSession.shared.data(from: url)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 404 { return [] }                       // Scryfall returns 404 for "no cards"
        guard code == 200 else { throw CardDatabaseError.badResponse }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return decoded.data.prefix(60).map {
            CardLookupResult(
                name: $0.name ?? "",
                setName: $0.set_name ?? "",
                number: $0.collector_number ?? "",
                rarity: ($0.rarity ?? "").capitalized,
                imageURL: $0.image_uris?.normal ?? $0.card_faces?.first?.image_uris?.normal ?? ""
            )
        }
    }

    private struct Response: Decodable { let data: [MTGCard] }
    private struct MTGCard: Decodable {
        let name: String?; let set_name: String?; let collector_number: String?; let rarity: String?
        let image_uris: Imgs?; let card_faces: [Face]?
    }
    private struct Face: Decodable { let image_uris: Imgs? }
    private struct Imgs: Decodable { let normal: String? }
}

// MARK: - Yu-Gi-Oh! (YGOPRODeck, no key)

struct YGOPRODeckProvider: CardDatabaseProvider {
    let gameCode = "YGO"
    let sourceName = "YGOPRODeck"

    func search(_ query: String, field: CardSearchField, apiKey: String) async throws -> [CardLookupResult] {
        guard var c = URLComponents(string: "https://db.ygoprodeck.com/api/v7/cardinfo.php") else { throw CardDatabaseError.badResponse }
        // Yu-Gi-Oh's printed "number" is the 8-digit passcode. Numeric → lookup by id;
        // otherwise fall back to a fuzzy name search so the user still gets results.
        let digits = query.trimmingCharacters(in: .whitespaces)
        if field == .number, digits.allSatisfy(\.isNumber), !digits.isEmpty {
            c.queryItems = [URLQueryItem(name: "id", value: digits)]
        } else {
            c.queryItems = [URLQueryItem(name: "fname", value: query)]
        }
        guard let url = c.url else { throw CardDatabaseError.badResponse }
        let (data, response) = try await URLSession.shared.data(from: url)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 400 { return [] }                       // 400 = no matches
        guard code == 200 else { throw CardDatabaseError.badResponse }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else { return [] }
        return decoded.data.prefix(60).map {
            let firstSet = $0.card_sets?.first
            return CardLookupResult(
                name: $0.name ?? "",
                setName: firstSet?.set_name ?? $0.type ?? "",
                number: firstSet?.set_code ?? String($0.id ?? 0),
                rarity: firstSet?.set_rarity ?? "",
                imageURL: $0.card_images?.first?.image_url ?? ""
            )
        }
    }

    private struct Response: Decodable { let data: [YGOCard] }
    private struct YGOCard: Decodable {
        let id: Int?; let name: String?; let type: String?
        let card_sets: [CSet]?; let card_images: [CImage]?
    }
    private struct CSet: Decodable { let set_name: String?; let set_code: String?; let set_rarity: String? }
    private struct CImage: Decodable { let image_url: String? }
}

// MARK: - Pokémon (pokemontcg.io, optional key)

struct PokemonTCGProvider: CardDatabaseProvider {
    let gameCode = "PKM"
    let sourceName = "pokemontcg.io"
    var requiresAPIKey: Bool { false }   // works without a key (rate-limited); key raises limits

    func search(_ query: String, field: CardSearchField, apiKey: String) async throws -> [CardLookupResult] {
        guard var c = URLComponents(string: "https://api.pokemontcg.io/v2/cards") else { throw CardDatabaseError.badResponse }
        let escaped = query.replacingOccurrences(of: "\"", with: "")
        let lucene = field == .number ? "number:\"\(escaped)\"" : "name:\"\(escaped)*\""
        c.queryItems = [
            URLQueryItem(name: "q", value: lucene),
            URLQueryItem(name: "pageSize", value: "60"),
            URLQueryItem(name: "orderBy", value: "name")
        ]
        guard let url = c.url else { throw CardDatabaseError.badResponse }
        var request = URLRequest(url: url)
        if !apiKey.isEmpty { request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key") }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw CardDatabaseError.badResponse }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return decoded.data.map {
            CardLookupResult(
                name: $0.name ?? "",
                setName: $0.set?.name ?? "",
                number: $0.number ?? "",
                rarity: $0.rarity ?? "",
                imageURL: $0.images?.large ?? $0.images?.small ?? ""
            )
        }
    }

    private struct Response: Decodable { let data: [PKMCard] }
    private struct PKMCard: Decodable {
        let name: String?; let number: String?; let rarity: String?
        let images: Imgs?; let set: SetInfo?
    }
    private struct Imgs: Decodable { let small: String?; let large: String? }
    private struct SetInfo: Decodable { let name: String? }
}
