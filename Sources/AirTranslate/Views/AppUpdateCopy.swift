enum AppUpdateCopy {
    static var title: String { text("Software Updates", "소프트웨어 업데이트", "ソフトウェア更新", "软件更新") }
    static var check: String { text("Check for Updates", "업데이트 확인", "更新を確認", "检查更新") }
    static var checking: String { text("Checking GitHub…", "GitHub 확인 중…", "GitHubを確認中…", "正在检查 GitHub…") }
    static var automatic: String { text("Wenyi checks GitHub for compatible releases.", "Wenyi가 GitHub에서 호환되는 릴리스를 확인합니다.", "文訳はGitHubで互換性のあるリリースを確認します。", "文译会在 GitHub 检查适用于本机的正式版。") }
    static var upToDate: String { text("No newer compatible release was found.", "호환되는 새 버전이 없습니다.", "互換性のある新しいバージョンはありません。", "目前没有适用于本机的更新。") }
    static var failed: String { text("Couldn’t check GitHub. Try again later.", "GitHub를 확인하지 못했습니다. 나중에 다시 시도하세요.", "GitHubを確認できませんでした。後でもう一度お試しください。", "无法检查 GitHub，请稍后重试。") }
    static var available: String { text("Wenyi Update Available", "Wenyi 업데이트 알림", "文訳の更新があります", "文译有新版本") }
    static var download: String { text("Go to Download", "다운로드 페이지 열기", "ダウンロードページを開く", "前往下载") }
    static var notifications: String { text("New Version Notifications", "새 버전 알림", "新バージョンの通知", "新版本通知") }
    static var notificationDetail: String { text("Show a macOS notification when an update is available.", "업데이트가 있으면 macOS 알림을 표시합니다.", "更新があるとmacOSに通知します。", "发现新版本时发送 macOS 通知。") }
    static var notificationDenied: String { text("Allow Wenyi notifications in System Settings.", "시스템 설정에서 Wenyi 알림을 허용하세요.", "システム設定で文訳の通知を許可してください。", "请在系统设置中允许文译发送通知。") }

    static func versionAvailable(_ version: String) -> String {
        text("Version \(version) is available on GitHub.", "GitHub에서 \(version) 버전을 다운로드할 수 있습니다.", "GitHubでバージョン\(version)を入手できます。", "版本 \(version) 已在 GitHub 发布。")
    }

    private static func text(_ en: String, _ ko: String, _ ja: String, _ zh: String) -> String {
        AppText.localized(english: en, korean: ko, japanese: ja, chineseSimplified: zh)
    }
}
