import Foundation

/// Builds a spreadsheet-friendly CSV of the inventory and writes it to a temp file for
/// sharing (AirDrop, Files, Mail, etc.). Prices are exported as plain numbers so they
/// sum/sort correctly in Excel/Numbers/Sheets.
enum CSVExporter {
    private static let columns = [
        "Short Code", "Game", "Name", "Set", "Card Number", "Rarity", "Condition",
        "Quantity", "Purchase Price", "Currency", "Purchase Date",
        "Sold", "Sale Price", "Sold Date", "Notes"
    ]

    static func csvString(for cards: [Card], currencyCode: String) -> String {
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withFullDate]

        var rows = [columns.map(escape).joined(separator: ",")]
        for c in cards.sorted(by: { $0.createdAt < $1.createdAt }) {
            let fields = [
                c.shortCode,
                c.gameSystem?.name ?? "",
                c.name,
                c.setName,
                c.cardNumber,
                c.rarity,
                c.condition.label,
                String(c.quantity),
                decimalString(c.purchasePrice),
                currencyCode,
                df.string(from: c.purchaseDate),
                c.isSold ? "Yes" : "No",
                c.isSold ? decimalString(c.salePrice) : "",
                c.soldDate.map { df.string(from: $0) } ?? "",
                c.notes
            ]
            rows.append(fields.map(escape).joined(separator: ","))
        }
        return rows.joined(separator: "\r\n")
    }

    /// Write the CSV to a temp file and return its URL.
    static func writeTempFile(for cards: [Card], currencyCode: String) throws -> URL {
        let csv = csvString(for: cards, currencyCode: currencyCode)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CardLedger-Inventory.csv")
        try csv.data(using: .utf8)?.write(to: url, options: .atomic)
        return url
    }

    private static func decimalString(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).description(withLocale: Locale(identifier: "en_US_POSIX"))
    }

    /// Quote a field and escape embedded quotes (RFC 4180).
    private static func escape(_ field: String) -> String {
        let needsQuote = field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r")
        let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
        return needsQuote ? "\"\(escaped)\"" : escaped
    }
}
