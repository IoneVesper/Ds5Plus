import SwiftUI

@MainActor
struct ContentView: View {
    @ObservedObject var model: AppViewModel
    @State private var isSettingsPresented = false
    @State private var isAddPresetSheetPresented = false
    @State private var leftColumnHeight: CGFloat = 0
    @State private var isCustomLightbarPopoverPresented = false

    init(model: AppViewModel) {
        self.model = model
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.97, green: 0.98, blue: 1.00),
                    Color(red: 0.93, green: 0.96, blue: 1.00),
                    Color(red: 0.98, green: 0.97, blue: 0.95)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    HStack(alignment: .top, spacing: 20) {
                        VStack(spacing: 20) {
                            deviceCard
                            lightbarCard
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
                        .background(
                            GeometryReader { proxy in
                                Color.clear
                                    .onAppear {
                                        if abs(leftColumnHeight - proxy.size.height) > 1 {
                                            leftColumnHeight = proxy.size.height
                                        }
                                    }
                                    .onChange(of: proxy.size.height) { _, newValue in
                                        if abs(leftColumnHeight - newValue) > 1 {
                                            leftColumnHeight = newValue
                                        }
                                    }
                            }
                        )

                        VStack(spacing: 20) {
                            audioDriverCard
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
                        .frame(minHeight: leftColumnHeight, alignment: .top)
                    }
                }
                .padding(24)
            }
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsSheet(model: model)
        }
        .sheet(isPresented: $isAddPresetSheetPresented) {
            AddAudioPresetSheet(model: model)
        }
        .frame(minWidth: 1120, minHeight: 760)
    }

    private var header: some View {
        glassCard {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("DS5+")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.16, green: 0.22, blue: 0.35))
                }
                .frame(maxHeight: .infinity, alignment: .center)

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 14) {
                    HStack(spacing: 12) {
                        toolbarButton(
                            systemName: "arrow.clockwise",
                            tint: Color.white.opacity(0.82),
                            symbolColor: Color(red: 0.24, green: 0.45, blue: 0.87),
                            helpText: "刷新蓝牙设备和音频捕获源".localized
                        ) {
                            Task {
                                await model.refreshAll()
                            }
                        }

                        toolbarButton(
                            systemName: model.runButtonSymbolName,
                            tint: model.runButtonTint.opacity(0.94),
                            symbolColor: .white,
                            helpText: model.isRunning ? "停止音频驱动".localized : "开始音频驱动".localized
                        ) {
                            model.toggleRunState()
                        }
                        .disabled(!model.canToggleRun && !model.isRunning)

                        toolbarButton(
                            systemName: "gearshape.fill",
                            tint: Color.white.opacity(0.82),
                            symbolColor: Color(red: 0.39, green: 0.44, blue: 0.58),
                            helpText: "打开设置与日志".localized
                        ) {
                            model.refreshLogFileMetadata()
                            isSettingsPresented = true
                        }
                    }

                    HStack(spacing: 10) {
                        statusPill(title: "连接".localized, value: model.connectionStatusText, tint: model.connectionStatusTint)
                        statusPill(title: "捕获".localized, value: model.captureStatusText, tint: model.captureEnabled ? Color(red: 0.24, green: 0.70, blue: 0.48) : Color(red: 0.65, green: 0.69, blue: 0.77))
                        statusPill(title: "运行".localized, value: model.runStatusText, tint: model.runStatusTint)
                    }
                }
            }
        }
    }

    private var deviceCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 18) {
                sectionTitle("连接".localized)

                VStack(alignment: .leading, spacing: 12) {
                    label("蓝牙 DualSense".localized)

                    selectionMenu(
                        title: model.selectedDevice?.displayName ?? "选择蓝牙 DualSense".localized,
                        accent: Color(red: 0.88, green: 0.93, blue: 1.00)
                    ) {
                        ForEach(model.devices) { device in
                            Button(device.displayName) {
                                model.selectedDeviceID = device.id
                            }
                        }
                    }

                    if model.selectedDevice == nil {
                        detail("请先在 macOS 蓝牙设置中连接 DualSense。".localized)
                    }
                }

                Divider()

                HStack(spacing: 12) {
                    infoTile(title: "捕获显示器".localized, value: model.captureStatusText)
                    infoTile(title: "手柄电量".localized, value: model.batteryPercentageText, valueColor: model.batteryTint)
                    infoTile(title: "灯条偏色".localized, value: model.lightbarDisplayTitle, valueColor: model.lightbarPreviewColor)
                }
            }
        }
    }

    private var lightbarCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    sectionTitle("灯条颜色".localized)
                    Spacer()
                    customLightbarButton
                }

                VStack(alignment: .leading, spacing: 8) {
                    label("运行时动态偏色".localized)
                    detail("可直接选预设颜色；点右上角“···”可自定义色相、饱和度与亮度。".localized)
                }

                let columns = Array(repeating: GridItem(.flexible(minimum: 54, maximum: 80), spacing: 12), count: 4)
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(LightbarColorPreset.allCases) { preset in
                        lightbarButton(for: preset)
                    }
                }
            }
        }
    }

    private var audioDriverCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 18) {
                sectionTitle("音频驱动".localized)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 12) {
                        label("音频预设".localized)
                        Spacer()
                        Button {
                            isAddPresetSheetPresented = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .buttonStyle(.bordered)
                        .tint(Color(red: 0.32, green: 0.47, blue: 0.87))
                        .help("将当前参数保存为自定义预设".localized)

                        Button("恢复默认".localized) {
                            model.restoreCurrentPresetDefaults()
                        }
                        .buttonStyle(.bordered)
                        .tint(Color(red: 0.32, green: 0.47, blue: 0.87))
                    }

                    selectionMenu(
                        title: model.currentPresetTitle,
                        accent: Color(red: 0.93, green: 0.95, blue: 1.00)
                    ) {
                        Section("内置预设".localized) {
                            ForEach(AudioReactivePreset.allCases) { preset in
                                Button(preset.title) {
                                    model.applyAudioPreset(preset, shouldLog: true)
                                }
                            }
                        }

                        if !model.customAudioPresets.isEmpty {
                            Section("自定义预设".localized) {
                                ForEach(model.customAudioPresets) { preset in
                                    Button(preset.name) {
                                        model.applyCustomAudioPreset(preset, shouldLog: true)
                                    }
                                }
                            }
                        }
                    }

                    detail(model.selectedCustomPreset?.basePreset.detail ?? model.audioPreset.detail)
                }

                Divider()

                VStack(spacing: 15) {
                    sliderRow(
                        title: "驱动增益".localized,
                        value: $model.audioDrive,
                        range: 0.5 ... 4.0,
                        helpText: "提高后整体震动更强、更容易触发；降低后更克制，适合避免持续轰鸣。".localized
                    )

                    sliderRow(
                        title: "噪声门限".localized,
                        value: $model.audioFloor,
                        range: 0.001 ... 0.08,
                        helpText: "提高后会过滤更多细小背景声与底噪；降低后更容易保留脚步、轻环境音。".localized
                    )

                    sliderRow(
                        title: "满刻度".localized,
                        value: $model.audioCeiling,
                        range: 0.03 ... 0.35,
                        helpText: "降低后更容易达到强震；提高后动态更宽，适合避免普通场景过强。".localized
                    )
                }

                Divider()

                Toggle(isOn: $model.audioSuppressMusic) {
                    VStack(alignment: .leading, spacing: 4) {
                        label("游戏模式".localized)
                        detail("优先保留音效、环境音、攻击与步态脉冲，同时压低背景音乐。".localized)
                    }
                }
                .toggleStyle(.switch)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var customLightbarButton: some View {
        Button {
            isCustomLightbarPopoverPresented.toggle()
        } label: {
            Text("···")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(model.isCustomLightbarColorSelected ? Color.white : Color(red: 0.42, green: 0.49, blue: 0.62))
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(model.isCustomLightbarColorSelected ? model.lightbarPreviewColor : Color.white.opacity(0.72))
                )
                .overlay(
                    Circle()
                        .strokeBorder(
                            model.isCustomLightbarColorSelected ? model.lightbarPreviewColor.opacity(0.95) : Color(red: 0.79, green: 0.84, blue: 0.92),
                            lineWidth: model.isCustomLightbarColorSelected ? 2 : 1
                        )
                )
                .shadow(
                    color: model.isCustomLightbarColorSelected ? model.lightbarPreviewColor.opacity(0.22) : Color(red: 0.58, green: 0.65, blue: 0.79).opacity(0.12),
                    radius: 10,
                    y: 4
                )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isCustomLightbarPopoverPresented, arrowEdge: .top) {
            CustomLightbarEditor(model: model)
                .padding(18)
        }
        .help("自定义灯条颜色".localized)
    }

    private func lightbarButton(for preset: LightbarColorPreset) -> some View {
        let rgb = preset.rgb
        let fill = Color(red: rgb.0, green: rgb.1, blue: rgb.2)
        let isSelected = !model.isCustomLightbarColorSelected && model.lightbarColorPreset == preset

        return Button {
            model.selectLightbarColor(preset)
        } label: {
            VStack(spacing: 8) {
                ZStack(alignment: .top) {
                    Circle()
                        .fill(isSelected ? fill.opacity(0.96) : fill.opacity(0.78))
                        .frame(width: 34, height: 34)
                        .overlay(
                            Circle()
                                .strokeBorder(isSelected ? fill.opacity(0.98) : Color.white.opacity(0.72), lineWidth: isSelected ? 2.5 : 1)
                        )
                        .shadow(color: fill.opacity(0.18), radius: 8, y: 4)

                }

                Text(preset.title)
                    .font(.caption)
                    .foregroundStyle(Color(red: 0.36, green: 0.40, blue: 0.50))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? fill.opacity(0.16) : Color.white.opacity(0.62))
            )
        }
        .buttonStyle(.plain)
    }

    private func glassCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
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

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.title3.weight(.semibold))
            .foregroundStyle(Color(red: 0.18, green: 0.24, blue: 0.35))
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .foregroundStyle(Color(red: 0.22, green: 0.28, blue: 0.40))
    }

    private func detail(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Color(red: 0.45, green: 0.51, blue: 0.61))
    }

    private func infoTile(title: String, value: String, subtitle: String? = nil, valueColor: Color = Color(red: 0.20, green: 0.26, blue: 0.37)) -> some View {
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

    private func statusPill(title: String, value: String, tint: Color) -> some View {
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

    private func toolbarButton(
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

    private func selectionMenu<Content: View>(
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

    private func sliderRow(
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

    private func valueText(_ value: Double) -> String {
        if value >= 1 {
            return value.formatted(.number.precision(.fractionLength(2)))
        }
        return value.formatted(.number.precision(.fractionLength(3)))
    }
}

private struct CustomLightbarEditor: View {
    @ObservedObject var model: AppViewModel

    private var hueBinding: Binding<Double> {
        Binding(
            get: { model.customLightbarHue },
            set: { model.updateCustomLightbar(hue: $0, preview: true) }
        )
    }

    private var saturationBinding: Binding<Double> {
        Binding(
            get: { model.customLightbarSaturation },
            set: { model.updateCustomLightbar(saturation: $0, preview: true) }
        )
    }

    private var brightnessBinding: Binding<Double> {
        Binding(
            get: { model.customLightbarBrightness },
            set: { model.updateCustomLightbar(brightness: $0, preview: true) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Circle()
                    .fill(model.lightbarPreviewColor)
                    .frame(width: 34, height: 34)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 1))
                    .shadow(color: model.lightbarPreviewColor.opacity(0.24), radius: 10, y: 4)

                VStack(alignment: .leading, spacing: 3) {
                    Text("自定义灯条".localized)
                        .font(.headline)
                        .foregroundStyle(Color(red: 0.18, green: 0.24, blue: 0.35))
                    Text("调整后会立即预览，并切换为自定义颜色。".localized)
                        .font(.caption)
                        .foregroundStyle(Color(red: 0.46, green: 0.52, blue: 0.62))
                }
            }

            customSlider(title: "色相".localized, value: hueBinding, range: 0 ... 1, accent: model.lightbarPreviewColor)
            customSlider(title: "饱和度".localized, value: saturationBinding, range: 0 ... 1, accent: model.lightbarPreviewColor)
            customSlider(title: "亮度".localized, value: brightnessBinding, range: 0.15 ... 1, accent: model.lightbarPreviewColor)
        }
        .frame(width: 280)
    }

    private func customSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        accent: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(red: 0.26, green: 0.31, blue: 0.43))
                Spacer()
                Text(value.wrappedValue.formatted(.number.precision(.fractionLength(2))))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color(red: 0.45, green: 0.50, blue: 0.60))
            }

            Slider(value: value, in: range)
                .tint(accent)
        }
    }
}

private struct AddAudioPresetSheet: View {
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

private struct HelpTooltip: View {
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

#Preview {
    ContentView(model: AppViewModel())
}
