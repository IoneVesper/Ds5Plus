import SwiftUI

struct CustomLightbarEditor: View {
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
