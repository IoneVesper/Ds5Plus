import SwiftUI

struct ContentView: View {
    @StateObject private var model = AppViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("DS5+ Bluetooth HID")
                .font(.largeTitle.bold())

            Text("通过 macOS 的 IOHIDManager 直接向蓝牙 DualSense 发送输出报告，不依赖 USB 音频或系统自带震动链路。")
                .foregroundStyle(.secondary)

            GroupBox("蓝牙 DualSense") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("设备", selection: $model.selectedDeviceID) {
                        ForEach(model.devices) { device in
                            Text(device.displayName).tag(Optional(device.id))
                        }
                    }
                    .pickerStyle(.menu)

                    if let device = model.selectedDevice {
                        Text("当前设备：\(device.name) · PID 0x\(String(device.productID, radix: 16, uppercase: true))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("请先在 macOS 蓝牙设置里配对 DualSense，连接后回到这里刷新。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            GroupBox("兼容振动输出") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("模式", selection: $model.mode) {
                        ForEach(HapticMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: model.mode) { _, _ in model.liveUpdateIfNeeded() }

                    sliderRow(title: "左电机", value: $model.leftMotor, range: 0 ... 255)
                        .onChange(of: model.leftMotor) { _, _ in model.liveUpdateIfNeeded() }
                    sliderRow(title: "右电机", value: $model.rightMotor, range: 0 ... 255)
                        .onChange(of: model.rightMotor) { _, _ in model.liveUpdateIfNeeded() }
                    sliderRow(title: "脉冲频率", value: $model.pulseFrequency, range: 1 ... 20, suffix: "Hz")
                        .onChange(of: model.pulseFrequency) { _, _ in model.liveUpdateIfNeeded() }

                    Text(model.mode.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                Button("开始持续输出") {
                    model.startEffect()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canStart)

                Button("发送单次脉冲") {
                    model.pulseOnce()
                }
                .buttonStyle(.bordered)
                .disabled(!model.canStart)

                Button("停止") {
                    model.stopEffect()
                }
                .buttonStyle(.bordered)

                Button("刷新设备") {
                    model.refreshDevices()
                }
                .buttonStyle(.bordered)

                Spacer()
                Text(model.statusLine)
                    .foregroundStyle(.secondary)
            }

            GroupBox("运行状态") {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("已发送报告") { Text("\(model.stats.sentReports)") }
                    LabeledContent("序号") { Text("\(model.stats.lastSequence)") }
                    LabeledContent("左/右电机") { Text("\(model.stats.lastLeftMotor) / \(model.stats.lastRightMotor)") }
                    LabeledContent("最近结果") { Text(model.stats.lastResult) }
                }
                .font(.system(.body, design: .monospaced))
            }

            GroupBox("日志") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(model.logs.indices, id: \.self) { index in
                            Text(model.logs[index])
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 220)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 720)
    }

    private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String = "") -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value.wrappedValue.rounded()))\(suffix.isEmpty ? "" : " \(suffix)")")
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }
}

#Preview {
    ContentView()
}
