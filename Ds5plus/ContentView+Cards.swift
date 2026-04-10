import SwiftUI

extension ContentView {
    var header: some View {
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
                        .disabled(!model.canRefreshServices)

                        toolbarButton(
                            systemName: model.runButtonSymbolName,
                            tint: model.runButtonTint.opacity(0.94),
                            symbolColor: .white,
                            helpText: (model.isRunning || model.isStarting) ? "停止音频驱动".localized : "开始音频驱动".localized
                        ) {
                            model.toggleRunState()
                        }
                        .disabled(!model.canToggleRun)

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

    var deviceCard: some View {
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

                VStack(alignment: .leading, spacing: 12) {
                    label("捕获显示器".localized)

                    selectionMenu(
                        title: model.captureSelectionTitle,
                        accent: Color(red: 0.93, green: 0.96, blue: 1.00)
                    ) {
                        ForEach(model.displays) { display in
                            Button(display.displayName) {
                                model.selectedDisplayID = display.id
                            }
                        }
                    }

                    if model.displays.isEmpty {
                        detail("当前没有可用的系统音频捕获源。".localized)
                    } else if model.selectedDisplay == nil {
                        detail("当前捕获显示器已不可用，请重新选择。".localized)
                    }
                }

                Divider()

                HStack(spacing: 12) {
                    infoTile(title: "捕获".localized, value: model.captureStatusText, subtitle: model.selectedDisplay?.displayName)
                    infoTile(title: "手柄电量".localized, value: model.batteryPercentageText, valueColor: model.batteryTint)
                    infoTile(title: "灯条偏色".localized, value: model.lightbarDisplayTitle, valueColor: model.lightbarPreviewColor)
                }
            }
        }
    }

    var lightbarCard: some View {
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

    var audioDriverCard: some View {
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

    var customLightbarButton: some View {
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

    func lightbarButton(for preset: LightbarColorPreset) -> some View {
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
}
