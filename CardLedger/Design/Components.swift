import SwiftUI

/// Reusable building blocks so screens share one visual language.

/// A rounded container card used to group content.
struct SurfaceCard<Content: View>: View {
    var padding: CGFloat = Theme.spacing4
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))
    }
}

/// Small pill showing a label + value, e.g. a stat or tag.
struct StatChip: View {
    var icon: String?
    var title: String
    var tint: Color = Theme.accent

    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon) }
            Text(title)
        }
        .font(.footnote.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.14), in: Capsule())
        .foregroundStyle(tint)
    }
}

/// Labelled value row for detail screens.
struct LabeledValue: View {
    var label: String
    var value: String
    var valueColor: Color = Theme.textPrimary

    var body: some View {
        HStack {
            Text(label).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value).foregroundStyle(valueColor).fontWeight(.semibold)
        }
        .font(.subheadline)
    }
}

/// Primary call-to-action button style.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.brandGradient, in: RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Empty-state placeholder.
struct EmptyStateView: View {
    var icon: String
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: Theme.spacing3) {
            Image(systemName: icon)
                .font(.system(size: 52))
                .foregroundStyle(Theme.accent.opacity(0.65))
            Text(title).font(.title3.weight(.semibold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.spacing6)
        .frame(maxWidth: .infinity)
    }
}
