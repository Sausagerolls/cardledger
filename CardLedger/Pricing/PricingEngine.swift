import Foundation

/// Pure, testable pricing math. No SwiftUI, no SwiftData — just numbers in, numbers out.
///
/// Default method (set in Settings): flat VAT applied to the full sale price.
///   net  = cost × (1 + profit)
///   sale = net × (1 + vat)
///
/// A future "VAT margin scheme" method (tax on profit only) can slot in here without
/// touching any view.
enum TaxMethod: String, CaseIterable, Identifiable, Codable {
    case fullPrice            // VAT on the whole sale price
    case marginScheme         // VAT on the margin (profit) only

    var id: String { rawValue }
    var label: String {
        switch self {
        case .fullPrice: return "VAT on full sale price"
        case .marginScheme: return "VAT margin scheme (profit only)"
        }
    }
}

struct PricingInput {
    /// Cost the trader paid, in major units.
    var cost: Decimal
    /// Target profit as a fraction, e.g. 0.10 for 10%.
    var profitMargin: Decimal
    /// VAT rate as a fraction, e.g. 0.20 for 20%.
    var vatRate: Decimal
    var method: TaxMethod
}

struct PricingResult {
    var salePrice: Decimal      // what to list it at
    var vatAmount: Decimal      // tax portion of the sale
    var netReceived: Decimal    // sale minus VAT
    var grossProfit: Decimal    // netReceived minus cost (the trader's take-home)
    var marginPercent: Decimal  // grossProfit / cost
}

enum PricingEngine {
    static func compute(_ input: PricingInput) -> PricingResult {
        let cost = input.cost
        let net = cost * (1 + input.profitMargin)

        let salePrice: Decimal
        let vatAmount: Decimal

        switch input.method {
        case .fullPrice:
            salePrice = net * (1 + input.vatRate)
            vatAmount = salePrice - net
        case .marginScheme:
            // VAT charged only on the margin between cost and net selling price.
            let margin = max(net - cost, 0)
            vatAmount = margin * input.vatRate
            salePrice = net + vatAmount
        }

        let netReceived = salePrice - vatAmount
        let grossProfit = netReceived - cost
        let marginPercent = cost > 0 ? grossProfit / cost : 0

        return PricingResult(
            salePrice: salePrice.rounded(2),
            vatAmount: vatAmount.rounded(2),
            netReceived: netReceived.rounded(2),
            grossProfit: grossProfit.rounded(2),
            marginPercent: marginPercent
        )
    }
}

extension Decimal {
    /// Round to `places` decimal places, banker's-free (plain round-half-up).
    func rounded(_ places: Int) -> Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, places, .plain)
        return result
    }
}
