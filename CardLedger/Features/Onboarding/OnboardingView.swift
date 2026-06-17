import SwiftUI

/// First-run tutorial + iCloud setup. Shown until the user finishes; can be replayed
/// from Settings.
struct OnboardingView: View {
    @Environment(SettingsStore.self) private var settings
    var onFinish: () -> Void

    @State private var page = 0

    private struct Step { let icon: String; let title: String; let body: String }
    private let steps: [Step] = [
        Step(icon: "rectangle.stack.fill.badge.plus",
             title: "Welcome to CardLedger",
             body: "Your trading-card stock, organised. Log what you buy, price it for profit, and find any card in seconds."),
        Step(icon: "camera.fill",
             title: "Log every card",
             body: "Tap + to add a card. Snap a photo or pull one from your library, set the price you paid, and pick the game. Buying multiples? Add several copies at once — each gets its own code."),
        Step(icon: "sterlingsign.circle.fill",
             title: "Price for profit",
             body: "Open a card and slide to your target profit. CardLedger shows the price to sell at with VAT and your real take-home worked out. Set your tax rate in Settings."),
        Step(icon: "qrcode",
             title: "Codes, QR & search",
             body: "Every copy gets a unique short code and QR. Print a sheet of them for your binders, then scan or search by the printed number or the code to jump straight to a card."),
        Step(icon: "wifi.router.fill",
             title: "View on your computer",
             body: "Turn on Desktop mode to browse, add and edit your inventory from any browser on the same Wi-Fi — handy on a big screen while you work.")
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(steps.indices, id: \.self) { i in
                    stepView(steps[i]).tag(i)
                }
                iCloudStep.tag(steps.count)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button(page == steps.count ? "Get Started" : "Continue") {
                if page == steps.count { finish() }
                else { withAnimation { page += 1 } }
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, Theme.spacing4)
            .padding(.bottom, Theme.spacing4)

            if page < steps.count {
                Button("Skip") { finish() }
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.bottom, Theme.spacing3)
            } else {
                Color.clear.frame(height: 28)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .interactiveDismissDisabled()
    }

    private func stepView(_ step: Step) -> some View {
        VStack(spacing: Theme.spacing4) {
            Spacer()
            ZStack {
                Circle().fill(Theme.accent.opacity(0.12)).frame(width: 160, height: 160)
                Image(systemName: step.icon)
                    .font(.system(size: 66))
                    .foregroundStyle(Theme.brandGradient)
            }
            Text(step.title)
                .font(.system(.title, design: .rounded).weight(.bold))
                .multilineTextAlignment(.center)
            Text(step.body)
                .font(.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.spacing6)
            Spacer(); Spacer()
        }
        .padding(Theme.spacing4)
    }

    private var iCloudStep: some View {
        VStack(spacing: Theme.spacing4) {
            Spacer()
            ZStack {
                Circle().fill(Theme.accent.opacity(0.12)).frame(width: 160, height: 160)
                Image(systemName: "icloud.fill").font(.system(size: 66)).foregroundStyle(Theme.brandGradient)
            }
            Text("Back up to iCloud")
                .font(.system(.title, design: .rounded).weight(.bold))
            Text("Keep your cards and photos safe and synced across your devices in your own private iCloud. Nothing is sent to us — your collection stays yours.")
                .font(.body).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center).padding(.horizontal, Theme.spacing5)

            SurfaceCard {
                Toggle(isOn: Binding(
                    get: { settings.iCloudSyncEnabled },
                    set: { settings.iCloudSyncEnabled = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("iCloud sync & backup").font(.headline)
                        Text("Recommended").font(.caption).foregroundStyle(Theme.profit)
                    }
                }
                .tint(Theme.profit)
            }
            .padding(.horizontal, Theme.spacing4)
            Text("You can change this any time in Settings.")
                .font(.caption).foregroundStyle(Theme.textSecondary)
            Spacer(); Spacer()
        }
        .padding(Theme.spacing4)
    }

    private func finish() {
        settings.hasCompletedOnboarding = true
        onFinish()
    }
}
