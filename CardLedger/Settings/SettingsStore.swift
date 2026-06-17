import Foundation
import SwiftUI

/// App-wide preferences backing the pricing engine. Persisted to `UserDefaults`
/// (and observable so views react instantly). Currency formatting lives here too.
@Observable
final class SettingsStore {
    var currencyCode: String { didSet { defaults.set(currencyCode, forKey: Keys.currency) } }
    /// VAT as a whole-number percent, e.g. 20.
    var vatPercent: Double { didSet { defaults.set(vatPercent, forKey: Keys.vat) } }
    /// Default target profit as a whole-number percent, e.g. 10.
    var defaultProfitPercent: Double { didSet { defaults.set(defaultProfitPercent, forKey: Keys.profit) } }
    var taxMethod: TaxMethod {
        didSet { defaults.set(taxMethod.rawValue, forKey: Keys.method) }
    }
    /// Optional API key for the card-database auto-fill provider.
    var cardApiKey: String { didSet { defaults.set(cardApiKey, forKey: Keys.apiKey) } }
    /// Whether the data store mirrors to the user's private iCloud. Read at launch to
    /// build the model container (see `PersistenceController`); changes apply next launch.
    var iCloudSyncEnabled: Bool { didSet { defaults.set(iCloudSyncEnabled, forKey: Keys.icloud) } }
    /// First-run onboarding completion.
    var hasCompletedOnboarding: Bool { didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.onboarded) } }

    /// The key `PersistenceController` reads (no SettingsStore instance needed there).
    static let iCloudSyncKey = "settings.iCloudSyncEnabled"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.currencyCode = defaults.string(forKey: Keys.currency) ?? "GBP"
        self.vatPercent = defaults.object(forKey: Keys.vat) as? Double ?? 20
        self.defaultProfitPercent = defaults.object(forKey: Keys.profit) as? Double ?? 10
        self.taxMethod = TaxMethod(rawValue: defaults.string(forKey: Keys.method) ?? "") ?? .fullPrice
        self.cardApiKey = defaults.string(forKey: Keys.apiKey) ?? ""
        self.iCloudSyncEnabled = defaults.object(forKey: Keys.icloud) as? Bool ?? true
        self.hasCompletedOnboarding = defaults.bool(forKey: Keys.onboarded)
    }

    var vatRate: Decimal { Decimal(vatPercent) / 100 }
    var defaultProfitMargin: Decimal { Decimal(defaultProfitPercent) / 100 }

    /// Format a Decimal as money in the user's chosen currency.
    func money(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }

    private enum Keys {
        static let currency = "settings.currencyCode"
        static let vat = "settings.vatPercent"
        static let profit = "settings.defaultProfitPercent"
        static let method = "settings.taxMethod"
        static let apiKey = "settings.cardApiKey"
        static let icloud = SettingsStore.iCloudSyncKey
        static let onboarded = "settings.hasCompletedOnboarding"
    }
}
