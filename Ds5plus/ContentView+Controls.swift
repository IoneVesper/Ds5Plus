import SwiftUI

extension ContentView {
    func glassCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(22)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.92),
                                Color(red: 0.96, green: 0.98, blue: 1.00).opacity(0.90),
                                Color(red: 0.95, green: 0.97, blue: 0.99).opacity(0.88)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.96), lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(Color(red: 0.81, green: 0.86, blue: 0.94).opacity(0.65), lineWidth: 1)
                    .padding(0.5)
            )
            .shadow(color: Color(red: 0.58, green: 0.66, blue: 0.83).opacity(0.08), radius: 14, y: 6)
    }

    func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.title3.weight(.semibold))
            .foregroundStyle(Color(red: 0.18, green: 0.24, blue: 0.35))
    }

    func label(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .foregroundStyle(Color(red: 0.22, green: 0.28, blue: 0.40))
    }

    func detail(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Color(red: 0.45, green: 0.51, blue: 0.61))
    }

    func infoTile(title: String, value: String, subtitle: String? = nil, valueColor: Color = Color(red: 0.20, green: 0.26, blue: 0.37)) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Color(red: 0.52, green: 0.58, blue: 0.68))
            Text(value)
                .font(.headline.weight(.semibold))
                .foregroundStyle(valueColor)
            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(Color(red: 0.50, green: 0.56, blue: 0.66))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .frame(minHeight: 86)
    }

    func statusPill(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Color(red: 0.51, green: 0.56, blue: 0.66))

            Text(value)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(tint, in: Capsule())
        }
    }

    func toolbarButton(
        systemName: String,
        tint: Color,
        symbolColor: Color,
        helpText: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(symbolColor)
                .frame(width: 46, height: 46)
                .background(tint, in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.94), lineWidth: 1))
                .shadow(color: tint.opacity(0.16), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .help(helpText)
    }

    func selectionMenu<Content: View>(
        title: String,
        accent: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(red: 0.19, green: 0.25, blue: 0.36))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 12)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(red: 0.39, green: 0.48, blue: 0.67))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(accent)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color(red: 0.70, green: 0.79, blue: 0.95), lineWidth: 1)
            )
            .shadow(color: Color(red: 0.57, green: 0.66, blue: 0.86).opacity(0.10), radius: 10, y: 4)
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
    }

    func sliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        helpText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                label(title)

                HelpTooltip(text: helpText)

                Spacer()

                Text(valueText(value.wrappedValue))
                    .foregroundStyle(Color(red: 0.42, green: 0.47, blue: 0.58))
                    .monospacedDigit()
            }

            Slider(value: value, in: range)
                .tint(Color(red: 0.29, green: 0.51, blue: 0.95))
        }
    }

    func valueText(_ value: Double) -> String {
        if value >= 1 {
            return value.formatted(.number.precision(.fractionLength(2)))
        }
        return value.formatted(.number.precision(.fractionLength(3)))
    }
}
