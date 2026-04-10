import SwiftUI

@MainActor
struct ContentView: View {
    @ObservedObject var model: AppViewModel
    @State var isSettingsPresented = false
    @State var isAddPresetSheetPresented = false
    @State var leftColumnHeight: CGFloat = 0
    @State var isCustomLightbarPopoverPresented = false

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
}

private struct ContentViewPreview: View {
    @StateObject private var model: AppViewModel

    init() {
        _model = StateObject(wrappedValue: AppViewModel.preview)
    }

    var body: some View {
        ContentView(model: model)
    }
}

#Preview {
    ContentViewPreview()
}
