import SwiftUI

struct SettingsSheet: View {
    @ObservedObject var model: AppViewModel
    @Environment(\.dismiss) private var dismiss

    private var logSizeBinding: Binding<LogFileSizeOption> {
        Binding(
            get: { model.logFileSizeOption },
            set: { model.updateLogFileSizeOption($0) }
        )
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.99, blue: 1.00),
                    Color(red: 0.95, green: 0.97, blue: 1.00),
                    Color(red: 0.99, green: 0.97, blue: 0.95)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("设置".localized)
                        .font(.largeTitle.bold())
                        .foregroundStyle(Color(red: 0.17, green: 0.23, blue: 0.35))
                    Spacer()
                    Button("完成".localized) {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.30, green: 0.50, blue: 0.93))
                }

                settingsCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("日志文件".localized)
                            .font(.headline)
                            .foregroundStyle(Color(red: 0.22, green: 0.28, blue: 0.40))

                        HStack {
                            settingsMeta(title: "当前大小".localized, value: model.currentLogFileSizeText)
                            settingsMeta(title: "最大大小".localized, value: model.logFileSizeOption.title)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("日志最大大小".localized)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color(red: 0.28, green: 0.34, blue: 0.46))

                            Picker("日志最大大小".localized, selection: logSizeBinding) {
                                ForEach(LogFileSizeOption.allCases) { option in
                                    Text(option.title).tag(option)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        Text(model.logFileURL.path)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Color(red: 0.46, green: 0.52, blue: 0.62))
                            .textSelection(.enabled)

                        HStack(spacing: 10) {
                            Button("刷新日志".localized) {
                                model.refreshLogFileMetadata()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color(red: 0.30, green: 0.50, blue: 0.93))

                            Button("在 Finder 中显示".localized) {
                                model.revealLogsInFinder()
                            }
                            .buttonStyle(.bordered)

                            Button("打开日志文件夹".localized) {
                                model.openLogsFolder()
                            }
                            .buttonStyle(.bordered)

                            Button("复制路径".localized) {
                                model.copyLogPath()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .padding(24)
        }
        .frame(width: 720, height: 380)
        .onAppear {
            model.refreshLogFileMetadata()
        }
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.94),
                                Color(red: 0.96, green: 0.98, blue: 1.00).opacity(0.90),
                                Color(red: 0.97, green: 0.97, blue: 0.98).opacity(0.88)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.96), lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(Color(red: 0.82, green: 0.87, blue: 0.95).opacity(0.62), lineWidth: 1)
                    .padding(0.5)
            )
            .shadow(color: Color(red: 0.60, green: 0.67, blue: 0.82).opacity(0.08), radius: 12, y: 5)
    }

    private func settingsMeta(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Color(red: 0.50, green: 0.56, blue: 0.67))
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(red: 0.20, green: 0.26, blue: 0.37))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.56), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
