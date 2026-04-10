import SwiftUI

struct AddAudioPresetSheet: View {
    @ObservedObject var model: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var presetName = ""

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
                Text("新建自定义预设".localized)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color(red: 0.18, green: 0.24, blue: 0.35))

                Text("会保存当前选中的基础预设、三个调节项，以及“游戏模式”开关状态。".localized)
                    .font(.subheadline)
                    .foregroundStyle(Color(red: 0.46, green: 0.52, blue: 0.62))

                VStack(alignment: .leading, spacing: 8) {
                    Text("预设名称".localized)
                        .font(.headline)
                        .foregroundStyle(Color(red: 0.22, green: 0.28, blue: 0.40))

                    TextField("例如：夜间轻震 / 动作游戏".localized, text: $presetName)
                        .textFieldStyle(.roundedBorder)
                }

                HStack {
                    Button("取消".localized) {
                        dismiss()
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("保存".localized) {
                        model.saveCustomAudioPreset(named: presetName)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.30, green: 0.50, blue: 0.93))
                }
            }
            .padding(24)
        }
        .frame(minWidth: 420, minHeight: 220)
    }
}
