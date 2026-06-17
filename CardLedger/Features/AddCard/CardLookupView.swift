import SwiftUI

/// Search a card database and pick a result to auto-fill the new-card form.
struct CardLookupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settings

    let gameCode: String
    var onPick: (CardLookupResult) -> Void

    @State private var query = ""
    @State private var field: CardSearchField = .name
    @State private var results: [CardLookupResult] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var provider: CardDatabaseProvider? { CardDatabaseRegistry.provider(for: gameCode) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let provider, provider.supportsNumberSearch {
                    Picker("Search by", selection: $field) {
                        ForEach(CardSearchField.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, Theme.spacing4)
                    .padding(.vertical, Theme.spacing2)
                    .onChange(of: field) { _, _ in if !query.isEmpty { Task { await runSearch() } } }
                }
            Group {
                if provider == nil {
                    EmptyStateView(icon: "tray", title: "Manual entry",
                                   message: "Auto-fill isn't available for this game yet. Close and type the details in.")
                } else if let errorMessage {
                    EmptyStateView(icon: "exclamationmark.triangle", title: "Couldn't search", message: errorMessage)
                } else if isLoading {
                    ProgressView("Searching…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if results.isEmpty {
                    EmptyStateView(icon: "magnifyingglass", title: "Search the database",
                                   message: provider.map { "Search by \(field.label.lowercased()).\nSource: \($0.sourceName)." }
                                        ?? "Type a card name and search.")
                } else {
                    List(results) { result in
                        Button { onPick(result); dismiss() } label: { resultRow(result) }
                    }
                }
            }
            }
            .navigationTitle("Auto-fill")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: field.prompt)
            .onSubmit(of: .search) { Task { await runSearch() } }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
    }

    private func resultRow(_ r: CardLookupResult) -> some View {
        HStack(spacing: Theme.spacing3) {
            AsyncImage(url: URL(string: r.imageURL)) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "rectangle.stack").foregroundStyle(Theme.textSecondary)
            }
            .frame(width: 44, height: 60).clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(r.name).font(.headline)
                Text([r.setName, r.number, r.rarity].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func runSearch() async {
        guard let provider, !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            results = try await provider.search(query, field: field, apiKey: settings.cardApiKey)
            if results.isEmpty { errorMessage = "No cards found for “\(query)”." }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
