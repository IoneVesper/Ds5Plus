import SwiftUI

struct AboutDs5plusView: View {
    @Environment(\.dismiss) private var dismiss

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.00"
    }

    private let projectInfo = "Wireless DualSense audio-reactive haptics driver for macOS over Bluetooth HID."
    private let developerName = "IoneVesper"
    private let buildDisplayVersion = "1.00"
    private let projectURLString = "https://github.com/IoneVesper/Ds5Plus"

    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 104, height: 104)
                .shadow(color: .black.opacity(0.12), radius: 10, y: 5)
                .padding(.top, 28)

            VStack(spacing: 6) {
                Text("Ds5Plus")
                    .font(.system(size: 22, weight: .bold))

                Text(String(format: "版本 %@".localized, appVersion))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                aboutRow(title: "项目信息".localized, value: projectInfo, multiline: true)
                aboutRow(title: "开发者".localized, value: developerName)
                aboutRow(title: "构建版本".localized, value: buildDisplayVersion)
                aboutLinkRow(title: "项目地址".localized, value: projectURLString)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.primary.opacity(0.04))
            )
            .padding(.horizontal, 24)

            Spacer()

            Button("关闭".localized) {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .padding(.bottom, 26)
        }
        .frame(width: 440, height: 520)
    }

    private func aboutRow(title: String, value: String, multiline: Bool = false) -> some View {
        HStack {
            if multiline {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .foregroundStyle(.secondary)
                    Text(value)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            } else {
                Text(title)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .textSelection(.enabled)
            }
        }
        .font(.subheadline)
    }

    private func aboutLinkRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Link(value, destination: URL(string: value)!)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.subheadline)
    }
}
