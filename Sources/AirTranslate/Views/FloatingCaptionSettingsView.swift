import AppKit
import SwiftUI

struct FloatingCaptionSettingsView: View {
    @Bindable var session: TranslationSessionStore
    @State private var showsAdvanced = false
    @State private var availableWidth: CGFloat = 0

    var body: some View {
        let wide = availableWidth >= 584
        let layout = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 24))
                          : AnyLayout(VStackLayout(alignment: .leading, spacing: 24))
        layout {
            preview.frame(maxWidth: wide ? .infinity : 480, alignment: .leading)
            controls.frame(width: wide ? 260 : nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppText.ui("字幕预览", "Caption preview", "字幕プレビュー")).font(.headline)
            FloatingCaptionScenePreview(session: session)
                .accessibilityIdentifier("unifiedCaptionScenePreview")
            Text(AppText.ui("媒体和实时字幕使用同一样式。调整后立即更新预览。", "Media and live captions share this appearance. Changes appear immediately.", "メディア字幕とリアルタイム字幕は同じ表示スタイルです。変更はプレビューにすぐ反映されます。"))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                FloatingCaptionWindowController.open(session: session, preview: true)
            } label: {
                Label(AppText.ui("在悬浮窗口中预览", "Preview in floating window", "フローティングウィンドウでプレビュー"), systemImage: "rectangle.on.rectangle")
            }
            .disabled(session.isRunning || session.isStarting)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(AppText.ui("字幕显示", "Caption display", "字幕表示")).font(.headline)
            Picker(AppText.floatingDisplay, selection: $session.floatingCaptionDisplayMode) {
                ForEach(session.availableFloatingCaptionDisplayModes) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            .disabled(session.isTranscribeOnlyMode)
            .accessibilityIdentifier("unifiedCaptionDisplayMode")
            Text(AppText.ui("黑色半透明背景 · 白色原文 · 黄色译文", "Translucent black · White original · Yellow translation", "半透明の黒背景・白い原文・黄色い訳文"))
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            DisclosureGroup(isExpanded: $showsAdvanced) {
                advancedOptions.padding(.top, 14)
            } label: {
                Text(AppText.ui("高级选项", "Advanced options", "詳細設定")).font(.headline)
            }
            .accessibilityIdentifier("unifiedCaptionAdvancedOptions")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var advancedOptions: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Stepper(value: pointSize, in: 18...72, step: 1) {
                    Text(AppText.ui("字号", "Font size", "文字サイズ") + " · \(Int(pointSize.wrappedValue)) pt")
                }
                Slider(value: pointSize, in: 18...72, step: 1)
                    .accessibilityLabel(AppText.ui("字幕字号", "Caption font size", "字幕の文字サイズ"))
            }
            Picker(AppText.ui("行间距", "Line spacing", "行間"), selection: $session.floatingCaptionStyle.lineSpacing) {
                ForEach(FloatingCaptionLineSpacing.allCases) { Text($0.title).tag($0) }
            }
            Picker(AppText.ui("窗口高度参考", "Window height", "ウィンドウの高さ"), selection: $session.floatingCaptionLineCount) {
                ForEach(FloatingCaptionLineCount.allCases) { Text($0.title).tag($0) }
            }
            Picker(AppText.captionAlignment, selection: $session.floatingCaptionTextAlignment) {
                ForEach(FloatingCaptionTextAlignment.allCases) { Text($0.title).tag($0) }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(AppText.ui("背景不透明度", "Background opacity", "背景の不透明度") + " · \(Int(session.floatingCaptionBackgroundOpacity * 100))%")
                Slider(value: $session.floatingCaptionBackgroundOpacity, in: 0.2...1, step: 0.05)
                    .accessibilityLabel(AppText.ui("背景不透明度", "Background opacity", "背景の不透明度"))
            }
            Toggle(CaptionStyleCopy.keepOnTop, isOn: $session.keepsFloatingCaptionAboveOtherWindows)
            Text(AppText.ui("使用系统字体。拖动字幕顶部可跨屏移动，拖动窗口边缘可调整大小。", "Uses the system font. Drag the header across displays or resize the window at its edges.", "システムフォントを使用します。上部をドラッグすると画面間で移動でき、ウィンドウの端でサイズを変更できます。"))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(AppText.ui("恢复默认", "Restore defaults", "既定値に戻す")) {
                session.resetFloatingCaptionAppearance()
            }
        }
        .pickerStyle(.menu)
    }

    private var pointSize: Binding<Double> {
        Binding(get: { Double(UnifiedFloatingCaptionStyle(session: session).pointSize) },
                set: { session.floatingCaptionCustomPointSize = CGFloat($0) })
    }
}

/// A 16:9 scene preview inspired by FluentRead's live preview arrangement.
/// The SwiftUI renderer below is the same one used in both floating windows.
private struct FloatingCaptionScenePreview: View {
    let session: TranslationSessionStore
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                LinearGradient(colors: [Color(red: 0.12, green: 0.22, blue: 0.28), Color(red: 0.3, green: 0.39, blue: 0.38)],
                               startPoint: .top, endPoint: .bottom)
                Image(systemName: "mountain.2.fill")
                    .resizable().scaledToFit().foregroundStyle(.white.opacity(0.08))
                    .padding(.horizontal, 35).padding(.bottom, 20)
                VStack(spacing: 14) {
                    Spacer(minLength: 0)
                    ScrollView {
                        UnifiedFloatingCaptionBlock(
                            source: AppText.ui("Every voice has a story.", "Every voice has a story.", "声には物語があります。"),
                            translation: AppText.ui("每个声音都有故事。", "声には物語があります。", "每个声音都有故事。"),
                            style: UnifiedFloatingCaptionStyle(session: session))
                            .padding(18)
                    }
                    .frame(maxHeight: max(80, geometry.size.height * 0.6))
                    .background(Color.black.opacity(UnifiedFloatingCaptionStyle(session: session).opacity),
                                in: RoundedRectangle(cornerRadius: UnifiedFloatingCaptionStyle.cornerRadius))
                    HStack(spacing: 10) {
                        Image(systemName: "play.fill")
                        Capsule().fill(.white.opacity(0.35)).frame(height: 3)
                        Image(systemName: "speaker.wave.2.fill")
                    }
                    .font(.caption).foregroundStyle(.white.opacity(0.7))
                }
                .padding(16)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .aspectRatio(16 / 9, contentMode: .fit)
    }
}
