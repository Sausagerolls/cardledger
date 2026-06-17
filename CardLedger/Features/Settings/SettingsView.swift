import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Query private var cards: [Card]

    @State private var exportFile: ExportFile?
    @State private var exportError: String?
    @State private var showOnboarding = false

    private let currencies = ["GBP", "USD", "EUR", "JPY", "AUD", "CAD"]

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section("Tax & pricing") {
                    Picker("Currency", selection: $settings.currencyCode) {
                        ForEach(currencies, id: \.self) { Text($0).tag($0) }
                    }
                    HStack {
                        Text("VAT rate")
                        Spacer()
                        TextField("20", value: $settings.vatPercent, format: .number)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 70)
                        Text("%").foregroundStyle(Theme.textSecondary)
                    }
                    HStack {
                        Text("Default profit")
                        Spacer()
                        TextField("10", value: $settings.defaultProfitPercent, format: .number)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 70)
                        Text("%").foregroundStyle(Theme.textSecondary)
                    }
                    Picker("Tax method", selection: $settings.taxMethod) {
                        ForEach(TaxMethod.allCases) { Text($0.label).tag($0) }
                    }
                }

                Section {
                    pricingExample
                } header: {
                    Text("Example")
                } footer: {
                    Text("Sale price for a card bought at \(settings.money(100)) at your default profit and VAT.")
                }

                Section("Card auto-fill") {
                    Text("Dragon Ball, Magic and Yu-Gi-Oh! auto-fill with no setup. Pokémon works too; a free pokemontcg.io key just raises the rate limit.")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                    SecureField("Pokémon API key (optional)", text: $settings.cardApiKey)
                }

                Section("Data") {
                    Button {
                        exportCSV()
                    } label: {
                        Label("Export inventory as CSV", systemImage: "square.and.arrow.up")
                    }
                    .disabled(cards.isEmpty)
                    Text("Spreadsheet of all \(cards.count) cards — opens in Numbers, Excel or Google Sheets.")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }

                Section {
                    Toggle("iCloud sync & backup", isOn: $settings.iCloudSyncEnabled)
                    LabeledValue(label: "Cards stored", value: "\(cards.count)")
                } header: {
                    Text("iCloud")
                } footer: {
                    Text("Backs up your cards and photos to your private iCloud and keeps them in sync across your devices. Turning this off keeps everything on this device only. Changes take effect next time you open the app.")
                }

                Section("Help") {
                    Button {
                        showOnboarding = true
                    } label: {
                        Label("Show tutorial again", systemImage: "questionmark.circle")
                    }
                }

                Section("About") {
                    LabeledValue(label: "Version", value: "1.0")
                    LabeledValue(label: "Made by", value: "Giant Mushroom Studio")
                    if let mail = URL(string: "mailto:contact@giantmushroom.studio") {
                        Link(destination: mail) {
                            Label("Contact support", systemImage: "envelope")
                        }
                    }
                    if let site = URL(string: "https://www.giantmushroom.studio/ledger") {
                        Link(destination: site) {
                            Label("Website", systemImage: "safari")
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .sheet(item: $exportFile) { file in
                ShareSheet(items: [file.url])
            }
            .fullScreenCover(isPresented: $showOnboarding) {
                OnboardingView { showOnboarding = false }.environment(settings)
            }
            .alert("Export failed", isPresented: .constant(exportError != nil)) {
                Button("OK") { exportError = nil }
            } message: { Text(exportError ?? "") }
        }
    }

    private func exportCSV() {
        do {
            let url = try CSVExporter.writeTempFile(for: cards, currencyCode: settings.currencyCode)
            exportFile = ExportFile(url: url)
        } catch {
            exportError = error.localizedDescription
        }
    }

    private var pricingExample: some View {
        let result = PricingEngine.compute(PricingInput(
            cost: 100,
            profitMargin: settings.defaultProfitMargin,
            vatRate: settings.vatRate,
            method: settings.taxMethod
        ))
        return VStack(spacing: 6) {
            LabeledValue(label: "List at", value: settings.money(result.salePrice), valueColor: Theme.accent)
            LabeledValue(label: "VAT", value: settings.money(result.vatAmount))
            LabeledValue(label: "Profit", value: settings.money(result.grossProfit), valueColor: Theme.profit)
        }
    }
}
