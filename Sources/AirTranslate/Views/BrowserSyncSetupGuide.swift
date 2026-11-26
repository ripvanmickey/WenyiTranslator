import SwiftUI

struct BrowserSyncSetupStep: Identifiable {
    let id: Int
    let title: MediaLocalizedText
    let detail: MediaLocalizedText
}

enum BrowserSyncSetup {
    static func steps(for browser: VideoPlaybackBrowser) -> [BrowserSyncSetupStep] {
        [
            .init(id: 1, title: .init("打开视频", "Open the video", "動画を開く"),
                  detail: .init("在所选浏览器打开目标 YouTube 标签页。进入媒体模式后会自动读取视频链接；手动编辑链接后可重新开启“自动读取当前标签页”。", "Open the target YouTube tab in the selected browser. Media mode fills its link automatically. After editing the link manually, you can re-enable automatic tab reading.", "選択したブラウザで対象の YouTube タブを開きます。メディアモードがリンクを自動入力します。手動編集後はタブの自動読み取りを再度有効にできます。")),
            .init(id: 2, title: .init("开启脚本权限", "Allow browser scripting", "スクリプトを許可"),
                  detail: browser == .chrome
                    ? .init("Chrome 菜单栏：显示 → 开发者 → 允许 Apple 事件中的 JavaScript。", "Chrome menu bar: View → Developer → Allow JavaScript from Apple Events.", "Chrome のメニューバー：表示 → 開発／管理 → Apple Events からの JavaScript を許可。")
                    : .init("Safari 菜单栏：开发 → 允许来自 Apple 事件的 JavaScript。没有“开发”菜单时，先在 Safari 设置 → 高级中启用网页开发者功能。", "Safari menu bar: Develop → Allow JavaScript from Apple Events. If Develop is hidden, enable web developer features in Safari Settings → Advanced first.", "Safari のメニューバー：開発 → Apple Events からの JavaScript を許可。「開発」がない場合は、Safari の設定 → 詳細で Web デベロッパ用の機能を表示します。")),
            .init(id: 3, title: .init("连接并允许自动化", "Connect and allow automation", "接続して自動操作を許可"),
                  detail: .init("首次读取时，在 macOS 弹窗中允许文译访问所选浏览器。确认字幕来源和翻译模型后，点击“连接当前视频”开始准备及同步。若曾拒绝，可在系统设置 → 隐私与安全性 → 自动化中重新允许，再重新开启自动读取。", "Allow Wenyi to access the selected browser in the first macOS prompt. Check the caption source and translation model, then click Connect video to prepare and sync. If access was denied, enable it in System Settings → Privacy & Security → Automation, then re-enable automatic tab reading.", "初回読み取り時に macOS の確認でブラウザへのアクセスを許可します。字幕ソースと翻訳モデルを確認し、「動画に接続」で準備と同期を開始します。拒否済みの場合は「システム設定 → プライバシーとセキュリティ → オートメーション」で許可し、自動読み取りを再度有効にします。")),
            .init(id: 4, title: .init("查看同步字幕", "Show synchronized captions", "同期字幕を表示"),
                  detail: .init("播放视频，首页字幕会跟随暂停、拖动与倍速。用首页顶部字幕按钮切换悬浮字幕；保持原视频标签页打开即可。", "Play the video. Captions follow pauses, seeking, and speed changes. Use the caption button at the top of the main window to toggle floating captions. Keep the linked video tab open.", "動画を再生すると、一時停止、シーク、速度変更に字幕が追従します。メイン画面上部の字幕ボタンでフローティング字幕を切り替えます。関連付けた動画タブは開いたままにしてください。"))
        ]
    }
}

struct BrowserSyncSetupGuide: View {
    let browser: VideoPlaybackBrowser
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false
    @State private var isPlaying = false
    @State private var phase = 0

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 14) {
                demonstration
                ForEach(BrowserSyncSetup.steps(for: browser)) { step in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(step.id)")
                            .font(.caption.weight(.semibold))
                            .frame(width: 22, height: 22)
                            .background(AirTranslateDesign.Palette.accentSoft, in: Circle())
                        VStack(alignment: .leading, spacing: 4) {
                            Text(step.title.value).font(.system(size: 12, weight: .semibold))
                            Text(step.detail.value).font(.system(size: 12)).foregroundStyle(.secondary)
                        }.fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.top, 10)
            .onDisappear { isPlaying = false }
        } label: {
            Label(AppText.ui("设置步骤与演示", "Setup steps & demo", "設定手順とデモ"), systemImage: "questionmark.circle")
                .font(.system(size: 12, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("browserSyncSetupGuide")
        .onChange(of: browser) { _, _ in phase = 0 }
        .onChange(of: isExpanded) { _, expanded in if !expanded { isPlaying = false } }
        .task(id: isPlaying) {
            guard isPlaying else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(1600)) }
                catch { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { phase = (phase + 1) % 4 }
            }
        }
    }

    private var demonstration: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(browser.title, systemImage: "globe").font(.caption.weight(.semibold))
                Spacer(minLength: 4)
                Text("\(phase + 1) / 4").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            ZStack(alignment: .leading) {
                Group {
                    switch phase {
                    case 0:
                        Label("YouTube", systemImage: "play.rectangle.fill")
                    case 1:
                        Label(AppText.ui("允许 Apple 事件中的 JavaScript", "Allow JavaScript from Apple Events", "Apple Events からの JavaScript を許可"), systemImage: "checkmark.square.fill")
                    case 2:
                        Label(AppText.ui("连接当前视频", "Connect video", "動画に接続"), systemImage: "link")
                    default:
                        VStack(alignment: .leading, spacing: 5) {
                            Text(AppText.ui("Hello, Wenyi!", "こんにちは、Wenyi！", "Hello, Wenyi!")).foregroundStyle(AirTranslateDesign.Palette.captionSource)
                            Text(AppText.ui("你好，文译！", "Hello, Wenyi!", "こんにちは、文訳！"))
                                .foregroundStyle(AirTranslateDesign.Palette.captionTranslation)
                        }
                    }
                }
                .font(.system(size: 13, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
                .id(phase).transition(.opacity)
            }
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
            .padding(10)
            .background(AirTranslateDesign.Palette.canvas, in: RoundedRectangle(cornerRadius: 10))
            HStack {
                Button {
                    if !isPlaying { phase = 0 }
                    isPlaying.toggle()
                } label: {
                    Label(isPlaying ? AppText.ui("暂停演示", "Pause demo", "デモを一時停止") : AppText.ui("播放演示", "Play demo", "デモを再生"), systemImage: isPlaying ? "pause.fill" : "play.fill")
                }.buttonStyle(.borderless)
                Spacer(minLength: 0)
            }
            Text(AppText.ui("示意动画，不会修改浏览器设置。", "Illustration only; browser settings are not changed.", "説明用のアニメーションです。ブラウザの設定は変更しません。"))
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(AirTranslateDesign.Palette.raised, in: RoundedRectangle(cornerRadius: 12))
    }
}
