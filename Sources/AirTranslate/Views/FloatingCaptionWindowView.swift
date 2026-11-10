import AppKit
import SwiftUI

struct FloatingCaptionTextSnapshot {
    let source: String
    let translation: String

    // 표시할 블록만 한 번씩 조판하고 창 상태 확인에서도 같은 결과를 사용한다.
    init(mode: FloatingCaptionDisplayMode, source: () -> String, translation: () -> String) {
        self.source = mode == .translation ? "" : source()
        self.translation = mode == .original ? "" : translation()
    }

    var hasVisibleText: Bool { !source.isEmpty || !translation.isEmpty }
}

// Keep the same CaptionLine identity, revisions and paragraph breaks as the main board.
// Keep recent content in a bounded viewport; expired paragraphs stay in the main board.
struct FloatingCaptionWindowView: View {
    @Bindable var session: TranslationSessionStore

    @State private var stable: [UUID: FloatingParagraphStability] = [:]
    @State private var visibility = FloatingParagraphVisibility()
    private static let previewID = UUID()

    private var paragraphs: [CaptionLine] {
        if session.isPreviewingFloatingCaptions {
            return [CaptionLine(id: Self.previewID, sourceText: CaptionStyleCopy.sampleOriginal,
                translatedText: CaptionStyleCopy.sampleTranslation, createdAt: .distantPast, isFinal: true)]
        }
        guard session.isFloatingCaptionPresentationActive else { return [] }
        return Array(session.lines.suffix(2))
    }

    private var visibleParagraphs: [CaptionLine] {
        visibility.hidesPrevious ? Array(paragraphs.suffix(1)) : paragraphs
    }
    private var preferredHeight: CGFloat { min(280, max(160, session.floatingCaptionPreferredWindowHeight)) }
    private var latestText: [String] {
        guard let line = paragraphs.last else { return [] }
        return [source(line), translation(line)]
    }
    private var latestID: UUID? { paragraphs.last?.id }
    private var hasText: Bool {
        visibleParagraphs.contains { line in
            (session.floatingCaptionDisplayMode != .translation && !source(line).isEmpty)
            || (session.floatingCaptionDisplayMode != .original && !translation(line).isEmpty)
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear
            if hasText {
                VStack(spacing: 0) {
                    // A small dedicated drag strip leaves text scrolling available.
                    FloatingCaptionDragSurface().frame(height: 12).help("拖动字幕窗口；在文字区域滚动查看完整段落")
                    ScrollViewReader { reader in
                        ScrollView(.vertical) {
                            VStack(alignment: .leading, spacing: 18) {
                                ForEach(visibleParagraphs) { line in
                                    paragraph(line)
                                        .id(line.id)
                                }
                            }
                            .overlay(alignment: .bottom) { Color.clear.frame(height: 1).id("live-bottom") }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 18).padding(.vertical, 8)
                            .background {
                                LinearGradient(stops: [
                                    .init(color: session.floatingCaptionBackgroundColor.opacity(session.floatingCaptionBackgroundOpacity * 0.65), location: 0),
                                    .init(color: session.floatingCaptionBackgroundColor.opacity(session.floatingCaptionBackgroundOpacity * 0.45), location: 0.8),
                                    .init(color: session.floatingCaptionBackgroundColor.opacity(session.floatingCaptionBackgroundOpacity * 0.12), location: 1)
                                ], startPoint: .top, endPoint: .bottom)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .frame(height: preferredHeight - 30)
                        .defaultScrollAnchor(.bottom)
                        .onChange(of: latestText) { old, new in
                            // Follow appended words, not late revisions of already read sentences.
                            if zip(old, new).contains(where: { !$0.1.isEmpty && $0.1 != $0.0 && $0.1.hasPrefix($0.0) }) {
                                reader.scrollTo("live-bottom", anchor: .bottom)
                            }
                        }
                        .onChange(of: latestID) { _, id in
                            // Follow a new paragraph once. Revisions never reposition the reader.
                            if let id { reader.scrollTo(id, anchor: .bottom) }
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(6)
            }
        }
        .frame(minWidth: FloatingCaptionWindowController.minimumWindowSize.width,
            idealWidth: FloatingCaptionWindowController.defaultWindowSize.width,
            maxWidth: .infinity, minHeight: session.floatingCaptionMinimumWindowHeight,
            idealHeight: preferredHeight, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            if session.isPreviewingFloatingCaptions {
                Button {
                    FloatingCaptionWindowController.close()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .padding(6)
                        .background(.regularMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .help(CaptionStyleCopy.closePreview)
                .accessibilityLabel(CaptionStyleCopy.closePreview)
                .padding(8)
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            session.floatingCaptionMeasuredTextWidth = max(0, size.width - 48)
            session.floatingCaptionMeasuredContentHeight = max(0, size.height - 40)
        }
        .onChange(of: paragraphs, initial: true) { _, _ in refresh() }
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                refresh()
            }
        }
        .onDisappear { stable.removeAll(); visibility = FloatingParagraphVisibility() }
        .wenyiWindowActivationEvents()
        .background(FloatingWindowConfigurator(preferredContentHeight: preferredHeight,
            minimumWindowSize: FloatingCaptionWindowController.minimumWindowSize,
            keepsAboveOtherWindows: session.keepsFloatingCaptionAboveOtherWindows,
            hasCaptionText: hasText))
    }

    private func source(_ line: CaptionLine) -> String {
        session.isPreviewingFloatingCaptions ? line.sourceDisplayText : stable[line.id]?.source.text ?? ""
    }

    private func translation(_ line: CaptionLine) -> String {
        if session.isPreviewingFloatingCaptions { return line.translatedDisplayText }
        return stable[line.id]?.translation.text ?? ""
    }

    private func refresh() {
        let now = ProcessInfo.processInfo.systemUptime
        let rows = paragraphs
        let live = Set(rows.map(\.id))
        stable = stable.filter { live.contains($0.key) }
        for line in rows {
            // Once a newer paragraph exists, preserve the old visible snapshot.
            // Its late corrections still update the full transcript, not this overlay.
            if line.id != rows.last?.id && stable[line.id] != nil { continue }
            var state = stable[line.id] ?? FloatingParagraphStability()
            state.source.receive(line.sourceDisplayText, final: line.isFinal, now: now)
            let translated = line.translatedDisplayText == AppText.translating ? "" : line.translatedDisplayText
            // ASR finality alone does not finalize a streaming translation.
            let finalTranslation = line.isFinal && line.isTranslationComplete
                && line.translatedSourceText == line.sourceText
            state.translation.receive(translated, final: finalTranslation, now: now, minimumFirstLength: 8)
            stable[line.id] = state
        }
        let current = rows.last
        visibility.update(latestID: current?.id,
            hasSource: current.map { !source($0).isEmpty } ?? false,
            hasTranslation: current.map { !translation($0).isEmpty } ?? false,
            requiresTranslation: session.floatingCaptionDisplayMode != .original, now: now)
    }

    @ViewBuilder private func paragraph(_ line: CaptionLine) -> some View {
        VStack(alignment: session.floatingCaptionTextAlignment == .center ? .center : .leading, spacing: 8) {
            switch session.floatingCaptionDisplayMode {
            case .original:
                text(source(line), primary: true)
            case .translation:
                text(translation(line), primary: true)
            case .originalAndTranslation:
                if session.floatingCaptionStyle.translationFirst {
                    text(translation(line), primary: true)
                    text(source(line), primary: false)
                } else {
                    text(source(line), primary: false)
                    text(translation(line), primary: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: session.floatingCaptionTextAlignment.frameAlignment(vertical: .top))
        .transaction { $0.animation = nil }
    }

    @ViewBuilder private func text(_ value: String, primary: Bool) -> some View {
        if !value.isEmpty {
            Text(value)
                .font(primary ? session.floatingCaptionPrimaryFont : session.floatingCaptionSecondaryFont)
                .foregroundStyle(session.floatingCaptionTextColor.opacity(primary ? 1 : 0.82))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(session.floatingCaptionTextAlignment.textAlignment)
                .lineSpacing(session.floatingCaptionStyle.lineSpacing.points)
                .frame(maxWidth: .infinity, alignment: session.floatingCaptionTextAlignment.frameAlignment(vertical: .top))
                .modifier(CaptionTextEffectModifier(effect: session.floatingCaptionStyle.textEffect))
        }
    }

    static func blockHeight(lineHeight: CGFloat, lineCount: Int) -> CGFloat {
        FloatingCaptionAppearance.blockHeight(lineHeight: lineHeight, lineCount: lineCount)
    }
}

private extension View {
    @ViewBuilder func wenyiWindowActivationEvents() -> some View {
        if #available(macOS 15.0, *) { self.allowsWindowActivationEvents(true) }
        else { self }
    }
}
