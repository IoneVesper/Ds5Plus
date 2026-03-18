import AppKit

enum MenuLocalizer {
    static func apply(language: AppLanguage, appName: String) {
        DispatchQueue.main.async {
            guard let mainMenu = NSApp.mainMenu else { return }
            localize(menu: mainMenu, language: language, appName: appName)
        }
    }

    private static func localize(menu: NSMenu, language: AppLanguage, appName: String) {
        for item in menu.items {
            item.title = localizedTitle(item.title, language: language, appName: appName)
            if let submenu = item.submenu {
                localize(menu: submenu, language: language, appName: appName)
            }
        }
    }

    private static func localizedTitle(_ title: String, language: AppLanguage, appName: String) -> String {
        let exactPairs: [(String, String)] = [
            ("File", "文件"),
            ("Edit", "编辑"),
            ("View", "视图"),
            ("Window", "窗口"),
            ("Help", "帮助"),
            ("Settings…", "设置…"),
            ("Settings...", "设置…"),
            ("Services", "服务"),
            ("Hide Others", "隐藏其他"),
            ("Show All", "显示全部"),
            ("Minimize", "最小化"),
            ("Zoom", "缩放"),
            ("Bring All to Front", "全部前置"),
            ("Close", "关闭"),
            ("Undo", "撤销"),
            ("Redo", "重做"),
            ("Cut", "剪切"),
            ("Copy", "复制"),
            ("Paste", "粘贴"),
            ("Delete", "删除"),
            ("Select All", "全选"),
            ("Start Dictation…", "开始听写…"),
            ("Start Dictation...", "开始听写…"),
            ("Emoji & Symbols", "表情与符号"),
            ("Enter Full Screen", "进入全屏"),
            ("Exit Full Screen", "退出全屏"),
            ("Full Screen", "全屏"),
            ("Find", "查找"),
            ("Spelling and Grammar", "拼写与语法"),
            ("Substitutions", "替换"),
            ("Transformations", "转换"),
            ("Speech", "语音"),
            ("Toolbar", "工具栏"),
            ("Show Toolbar", "显示工具栏"),
            ("Hide Toolbar", "隐藏工具栏"),
            ("Customize Toolbar…", "自定工具栏…"),
            ("Customize Toolbar...", "自定工具栏…"),
            ("Show Sidebar", "显示边栏"),
            ("Hide Sidebar", "隐藏边栏"),
            ("Show Tab Bar", "显示标签栏"),
            ("Hide Tab Bar", "隐藏标签栏"),
            ("Show Previous Tab", "显示上一个标签"),
            ("Show Next Tab", "显示下一个标签"),
            ("Move Tab to New Window", "将标签移到新窗口"),
            ("Merge All Windows", "合并所有窗口"),
            ("Help", "帮助")
        ]

        for (english, chinese) in exactPairs {
            if title == english || title == chinese {
                return language == .chinese ? chinese : english
            }
        }

        if title.hasPrefix("About \(appName)") || title.hasPrefix("关于 ") {
            return language == .chinese ? "关于 \(appName)…" : "About \(appName)…"
        }

        if title == "Hide \(appName)" || title == "隐藏 \(appName)" {
            return language == .chinese ? "隐藏 \(appName)" : "Hide \(appName)"
        }

        if title == "Quit \(appName)" || title == "退出 \(appName)" {
            return language == .chinese ? "退出 \(appName)" : "Quit \(appName)"
        }

        if title.hasPrefix("Show ") && title.contains("Tab") {
            return language == .chinese ? title.replacingOccurrences(of: "Show ", with: "显示 ") : title
        }

        return title
    }
}
