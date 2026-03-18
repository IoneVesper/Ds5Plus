import SwiftUI

@main
struct Ds5plusApp: App {
    @StateObject private var model = AppViewModel()
    @StateObject private var languageManager = LanguageManager.shared
    @State private var showAboutSheet = false

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .environment(\.locale, languageManager.language.locale)
                .id(languageManager.language.rawValue)
                .task(id: languageManager.language) {
                    MenuLocalizer.apply(language: languageManager.language, appName: "Ds5plus")
                }
                .sheet(isPresented: $showAboutSheet) {
                    AboutDs5plusView()
                        .environment(\.locale, languageManager.language.locale)
                        .id(languageManager.language.rawValue)
                }
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("关于 Ds5Plus…".localized) {
                    showAboutSheet = true
                }
            }

            CommandMenu("语言".localized) {
                ForEach(AppLanguage.allCases) { language in
                    Button(language.menuTitle) {
                        languageManager.language = language
                    }
                }
            }

            CommandMenu("日志".localized) {
                SettingsLink {
                    Text("打开设置".localized)
                }

                Divider()

                Button("打开日志文件夹（菜单）".localized) {
                    model.openLogsFolder()
                }

                Button("在 Finder 中显示日志".localized) {
                    model.revealLogsInFinder()
                }

                Button("复制日志路径".localized) {
                    model.copyLogPath()
                }

                Divider()

                Button("清空日志".localized) {
                    model.clearLogs()
                }
            }
        }

        Settings {
            SettingsSheet(model: model)
                .environment(\.locale, languageManager.language.locale)
                .id(languageManager.language.rawValue)
        }
    }
}
