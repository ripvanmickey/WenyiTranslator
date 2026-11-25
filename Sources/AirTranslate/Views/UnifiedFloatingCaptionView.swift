import AppKit
import SwiftUI

/// One presentation contract for live captions, media captions and the settings preview.
/// Legacy skin values remain readable but no longer change fonts, colors or ordering.
struct UnifiedFloatingCaptionStyle {
    var pointSize: CGFloat = 23
    var lineSpacing: CGFloat = 5
    var alignment: FloatingCaptionTextAlignment = .leading
    var opacity: Double = 0.8
    var mode: FloatingCaptionDisplayMode = .originalAndTranslation

    @MainActor init(session: TranslationSessionStore? = nil) {
        guard let session else { return }
        pointSize = session.floatingCaptionPrimaryPointSize
        lineSpacing = session.floatingCaptionStyle.lineSpacing.points
        alignment = session.floatingCaptionTextAlignment
        opacity = session.floatingCaptionBackgroundOpacity
        mode = session.floatingCaptionDisplayMode
    }
    var sourcePointSize: CGFloat { pointSize * 18 / 23 }
    static let cornerRadius: CGFloat = 18
}

struct UnifiedFloatingCaptionText: View {
    let value: String
    let isTranslation: Bool
    let style: UnifiedFloatingCaptionStyle
    var body: some View {
        Text(value)
            .font(.system(size: isTranslation ? style.pointSize : style.sourcePointSize,
                          weight: isTranslation ? .medium : .regular))
            .foregroundStyle(isTranslation ? FloatingCaptionAppearance.translationTextColor : .white)
            .lineSpacing(style.lineSpacing)
            .multilineTextAlignment(style.alignment.textAlignment)
            .frame(maxWidth: .infinity, alignment: style.alignment.frameAlignment(vertical: .top))
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }
}

struct UnifiedFloatingCaptionBlock: View {
    let source: String
    let translation: String
    let style: UnifiedFloatingCaptionStyle
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if style.mode != .translation, !source.isEmpty {
                UnifiedFloatingCaptionText(value: source, isTranslation: false, style: style)
            }
            if style.mode != .original, !translation.isEmpty {
                UnifiedFloatingCaptionText(value: translation, isTranslation: true, style: style)
            }
        }
        .transaction { $0.animation = nil }
    }
}

struct UnifiedFloatingCaptionSurface<Content: View>: View {
    let title: String
    let style: UnifiedFloatingCaptionStyle
    let close: () -> Void
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal")
                    Text(title)
                    Spacer(minLength: 0)
                }
                .font(.caption).foregroundStyle(.white.opacity(0.6))
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                .overlay { FloatingCaptionDragSurface().accessibilityHidden(true) }
                .help(AppText.ui("拖动这里移动字幕，可跨屏幕移动", "Drag here to move captions across displays", "ここをドラッグして字幕を別の画面にも移動できます"))
                Button(action: close) { Image(systemName: "xmark") }
                    .buttonStyle(.plain).foregroundStyle(.white)
                    .help(AppText.ui("关闭字幕", "Close captions", "字幕を閉じる"))
                    .accessibilityLabel(AppText.ui("关闭字幕", "Close captions", "字幕を閉じる"))
            }
            content
        }
        .padding(18)
        .background(Color.black.opacity(style.opacity), in: RoundedRectangle(cornerRadius: UnifiedFloatingCaptionStyle.cornerRadius))
    }
}
