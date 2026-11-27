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
    @State private var retainedTranslation: CaptionLine?
    @State private var measuredCaptionHeight: CGFloat = 48
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
        let recent = paragraphs
        let ids = visibility.visibleIDs(recent: recent.map(\.id), retainedTranslationID: retainedTranslation?.id,
            latestHasTranslation: recent.last.map { !translation($0).isEmpty } ?? false,
            requiresTranslation: requiresTranslation)
        return ids.compactMap { id in recent.first { $0.id == id } ?? (retainedTranslation?.id == id ? retainedTranslation : nil) }
    }
    private var requiresTranslation: Bool { session.floatingCaptionDisplayMode != .original }
    private var waitingForSuccessor: Bool {
        guard requiresTranslation, !session.isPreviewingFloatingCaptions,
              let latest = paragraphs.last, let retainedTranslation, latest.id != retainedTranslation.id else { return false }
        return translation(latest).isEmpty && !translation(retainedTranslation).isEmpty
    }
    private var preferredHeight: CGFloat { FloatingCaptionAppearance.compactWindowHeight(contentHeight: measuredCaptionHeight) }
    private var latestText: [String] {
        guard let line = paragraphs.last else { return [] }
        return [source(line), translation(line)]
    }
    private var latestID: UUID? { paragraphs.last?.id }
    private var hasText: Bool {
        visibleParagraphs.contains { line in
            (session.floatingCaptionDisplayMode != .translation && !source(line).isEmpty)
            || (requiresTranslation && !translation(line).isEmpty)
            || (requiresTranslation && session.isUsingLocalTranslation && line.isTranslationInterrupted)
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear
            if hasText {
                UnifiedFloatingCaptionSurface(title: AppText.ui("实时字幕", "Live captions", "リアルタイム字幕"),
                    style: UnifiedFloatingCaptionStyle(session: session), close: { FloatingCaptionWindowController.close() }) {
                    ScrollViewReader { reader in
                        ScrollView(.vertical) {
                            VStack(alignment: .leading, spacing: 18) {
                                if waitingForSuccessor, let retainedTranslation, let latest = paragraphs.last {
                                    if session.floatingCaptionDisplayMode == .originalAndTranslation {
                                        text(source(latest), primary: false)
                                    }
                                    translationBlock(retainedTranslation, primary: true, previous: true)
                                } else {
                                    ForEach(visibleParagraphs) { line in
                                        paragraph(line).id(line.id)
                                    }
                                }
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measuredCaptionHeight = $0 }
                            .overlay(alignment: .bottom) { Color.clear.frame(height: 1).id("live-bottom") }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: preferredHeight - FloatingCaptionAppearance.compactWindowChromeHeight)
                        .defaultScrollAnchor(.bottom)
                        .onChange(of: latestText) { old, new in
                            // Follow appended words, not late revisions of already read sentences.
                            if zip(old, new).contains(where: { !$0.1.isEmpty && $0.1 != $0.0 && $0.1.hasPrefix($0.0) }) {
                                reader.scrollTo("live-bottom", anchor: .bottom)
                            }
                        }
                        .onChange(of: latestID) { _, id in
                            // Follow a new paragraph once. Revisions never reposition the reader.
                            if waitingForSuccessor { reader.scrollTo("live-bottom", anchor: .bottom) }
                            else if let id { reader.scrollTo(id, anchor: .bottom) }
                        }
                    }
                }
            }
        }
        .frame(minWidth: FloatingCaptionWindowController.minimumWindowSize.width,
            idealWidth: session.floatingCaptionWindowWidth,
            maxWidth: .infinity, minHeight: FloatingCaptionWindowController.minimumWindowSize.height,
            idealHeight: preferredHeight, maxHeight: .infinity)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            session.floatingCaptionMeasuredTextWidth = max(0, size.width - 48)
            session.floatingCaptionMeasuredContentHeight = max(0, size.height - 40)
        }
        .onChange(of: paragraphs, initial: true) { _, _ in refresh() }
        .onChange(of: session.floatingCaptionDisplayMode) { _, _ in
            visibility = FloatingParagraphVisibility()
            refresh()
        }
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                refresh()
            }
        }
        .onDisappear { stable.removeAll(); visibility = FloatingParagraphVisibility(); retainedTranslation = nil }
        .wenyiWindowActivationEvents()
        .background(FloatingWindowConfigurator(preferredContentHeight: preferredHeight,
            preferredWindowWidth: session.floatingCaptionWindowWidth,
            minimumWindowSize: FloatingCaptionWindowController.minimumWindowSize,
            keepsAboveOtherWindows: session.keepsFloatingCaptionAboveOtherWindows,
            hasCaptionText: hasText,
            onWidthChanged: { session.floatingCaptionWindowWidth = $0 }))
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
        if rows.isEmpty || session.isPreviewingFloatingCaptions { retainedTranslation = nil }
        let usesLocalPreview = session.isUsingLocalTranslation
        for line in rows {
            // The legacy path freezes the preceding paragraph. Local translation can
            // still confirm it while it remains in the two-paragraph overlay.
            if !usesLocalPreview, line.id != rows.last?.id && stable[line.id] != nil { continue }
            var state = stable[line.id] ?? FloatingParagraphStability()
            state.source.receive(line.sourceDisplayText, final: line.isFinal, now: now, usesLocalPreview: usesLocalPreview)
            let translated = line.hasUsableTranslation ? line.translatedDisplayText : ""
            // ASR finality alone does not finalize a streaming translation.
            state.translation.receive(translated, final: line.hasConfirmedTranslation, now: now,
                minimumFirstLength: 8, usesLocalPreview: usesLocalPreview)
            stable[line.id] = state
        }
        if !session.isPreviewingFloatingCaptions, requiresTranslation,
           let newestTranslated = rows.last(where: { !translation($0).isEmpty }) {
            retainedTranslation = newestTranslated
        } else if !requiresTranslation {
            retainedTranslation = nil
        }
        var live = Set(rows.map(\.id))
        if let retainedTranslation { live.insert(retainedTranslation.id) }
        stable = stable.filter { live.contains($0.key) }
        let current = rows.last
        visibility.update(latestID: current?.id,
            hasSource: current.map { !source($0).isEmpty } ?? false,
            hasTranslation: current.map { !translation($0).isEmpty } ?? false,
            requiresTranslation: requiresTranslation, now: now)
    }

    @ViewBuilder private func paragraph(_ line: CaptionLine) -> some View {
        VStack(alignment: session.floatingCaptionTextAlignment == .center ? .center : .leading, spacing: 8) {
            switch session.floatingCaptionDisplayMode {
            case .original:
                text(source(line), primary: true)
            case .translation:
                translationBlock(line, primary: true)
            case .originalAndTranslation:
                text(source(line), primary: false)
                translationBlock(line, primary: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: session.floatingCaptionTextAlignment.frameAlignment(vertical: .top))
        .transaction { $0.animation = nil }
    }

    @ViewBuilder private func translationBlock(_ line: CaptionLine, primary: Bool, previous: Bool = false) -> some View {
        let value = translation(line)
        text(value, primary: primary, isTranslation: true)
    }

    @ViewBuilder private func text(_ value: String, primary: Bool, isTranslation: Bool = false) -> some View {
        if !value.isEmpty {
            UnifiedFloatingCaptionText(value: value, isTranslation: isTranslation,
                style: UnifiedFloatingCaptionStyle(session: session))
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
