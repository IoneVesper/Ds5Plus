import SwiftUI

struct HelpTooltip: View {
    let text: String
    @State private var isHovering = false

    var body: some View {
        Button {} label: {
            Image(systemName: "questionmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(red: 0.50, green: 0.56, blue: 0.70))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topLeading) {
            if isHovering {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(Color(red: 0.20, green: 0.24, blue: 0.34))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.98))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color(red: 0.82, green: 0.86, blue: 0.95), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.10), radius: 12, y: 6)
                    .frame(width: 240, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .offset(x: 18, y: -10)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
        .help(text)
        .zIndex(isHovering ? 10 : 0)
    }
}
