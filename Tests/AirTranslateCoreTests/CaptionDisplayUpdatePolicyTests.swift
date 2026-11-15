import Foundation
import Testing
@testable import AirTranslate

@Suite
struct CaptionDisplayUpdatePolicyTests {
    private let policy = CaptionDisplayUpdatePolicy(rewriteHoldDuration: 0.28)
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    @Test
    func localPreviewShowsFirstTextAndCoalescesAppends() {
        var caption = LiveLocalCaptionText()
        caption.receive("今", confirmed: false, now: 1)
        #expect(caption.text == "今")
        caption.receive("今天天气", confirmed: false, now: 1.1)
        #expect(caption.text == "今")
        #expect(caption.nextUpdateAt == 1.25)
        caption.receive("今天天气不错", confirmed: false, now: 1.25)
        #expect(caption.text == "今天天气不错")
        caption.receive("明天天气不错", confirmed: false, now: 1.5)
        #expect(caption.text == "今天天气不错")
        caption.receive("明天天气不错", confirmed: false, now: 2.1)
        #expect(caption.text == "明天天气不错")
        caption.receive("明天天气会很好。", confirmed: true, now: 2.11)
        caption.receive("明天天气晴朗。", confirmed: true, now: 3)
        #expect(caption.text == "明天天气会很好。")
        #expect(caption.nextUpdateAt == nil)
    }

    @Test
    func localFloatingPreviewDisplaysShortTextImmediately() {
        var channel = FloatingParagraphStability.Channel()
        channel.receive("好", final: false, now: 1, minimumFirstLength: 8, usesLocalPreview: true)
        #expect(channel.text == "好")
        channel.receive("好的，我们开始。", final: true, now: 1.1, minimumFirstLength: 8, usesLocalPreview: true)
        #expect(channel.text == "好的，我们开始。")
    }

    @Test
    func clearingUnconfirmedCandidateCancelsScheduledPreview() {
        var caption = LiveLocalCaptionText()
        caption.receive("今", confirmed: false, now: 1)
        caption.receive("今天", confirmed: false, now: 1.1)
        caption.receive("", confirmed: false, now: 1.2)
        #expect(caption.text == "今")
        #expect(caption.nextUpdateAt == nil)
    }

    @Test
    func floatingRetainsLastTranslationAcrossUntranslatedParagraphs() {
        let previous = UUID()
        let pending = UUID()
        let latest = UUID()
        var visibility = FloatingParagraphVisibility()
        visibility.update(latestID: latest, hasSource: true, hasTranslation: false, requiresTranslation: true, now: 1)
        visibility.update(latestID: latest, hasSource: true, hasTranslation: false, requiresTranslation: true, now: 5)
        #expect(!visibility.hidesPrevious)
        #expect(visibility.visibleIDs(recent: [pending, latest], retainedTranslationID: previous,
                                     latestHasTranslation: false, requiresTranslation: true) == [previous, latest])
        visibility.update(latestID: latest, hasSource: true, hasTranslation: true, requiresTranslation: true, now: 6)
        #expect(!visibility.hidesPrevious)
        visibility.update(latestID: latest, hasSource: true, hasTranslation: true, requiresTranslation: true, now: 7)
        #expect(visibility.hidesPrevious)
    }

    @Test
    func localTranslationStatusSeparatesPreviewCompletionAndInterruption() {
        var line = CaptionLine(sourceText: "原文", translatedText: "译文", translatedSourceText: "原文",
                               createdAt: start, isFinal: true)
        #expect(line.localTranslationStatus == "预览")
        line.isTranslationInterrupted = true
        #expect(line.localTranslationStatus == "中断")
        #expect(line.hasUsableTranslation)
        let completed = CaptionLine(sourceText: "原文", translatedText: "译文", translatedSourceText: "原文",
                                    createdAt: start, isFinal: true, isTranslationComplete: true)
        #expect(completed.localTranslationStatus == "已完成")
        var waiting = CaptionLine(sourceText: "原文", translatedText: AppText.translating, createdAt: start, isFinal: true)
        #expect(waiting.localTranslationStatus == "等待译文")
        waiting.isTranslationInterrupted = true
        #expect(waiting.localTranslationStatus == "中断")
        #expect(!waiting.hasUsableTranslation)
    }

    @Test
    func firstCaptionAndPrefixAppendPublishWithoutHold() {
        var state = CaptionDisplayUpdatePolicy.State()

        #expect(policy.receive("I", at: start, canHoldRewrite: true, state: &state) == .published("I"))
        #expect(state.visibleText == "I")

        let appendedAt = start.addingTimeInterval(0.01)
        #expect(
            policy.receive("I can hear you", at: appendedAt, canHoldRewrite: true, state: &state)
                == .published("I can hear you")
        )
        #expect(state.pendingRewriteText == nil)
        #expect(state.rewriteHoldUntil == nil)
    }

    @Test
    func nonPrefixRewriteIsHeldInsideBoundedWindow() {
        var state = CaptionDisplayUpdatePolicy.State(visibleText: "I")
        let rewriteAt = start.addingTimeInterval(0.02)
        let expectedHoldUntil = rewriteAt.addingTimeInterval(0.28)

        #expect(
            policy.receive("나", at: rewriteAt, canHoldRewrite: true, state: &state)
                == .held(until: expectedHoldUntil)
        )
        #expect(state.visibleText == "I")
        #expect(state.pendingRewriteText == "나")
        #expect(state.rewriteHoldUntil == expectedHoldUntil)

        let earlyFlush = policy.flushDueRewrite(
            at: expectedHoldUntil.addingTimeInterval(-0.001),
            state: &state
        )
        #expect(earlyFlush == .held(until: expectedHoldUntil))
        #expect(state.visibleText == "I")
    }

    @Test
    func heldRewriteKeepsLatestCandidateAndFlushesAtOriginalDeadline() {
        var state = CaptionDisplayUpdatePolicy.State(visibleText: "I")
        let firstRewriteAt = start.addingTimeInterval(0.02)
        let expectedHoldUntil = firstRewriteAt.addingTimeInterval(0.28)

        #expect(
            policy.receive("나", at: firstRewriteAt, canHoldRewrite: true, state: &state)
                == .held(until: expectedHoldUntil)
        )

        #expect(
            policy.receive(
                "나는 전체 문장을 듣고 있어요",
                at: firstRewriteAt.addingTimeInterval(0.18),
                canHoldRewrite: true,
                state: &state
            ) == .held(until: expectedHoldUntil)
        )
        #expect(state.visibleText == "I")
        #expect(state.pendingRewriteText == "나는 전체 문장을 듣고 있어요")

        #expect(
            policy.flushDueRewrite(
                at: expectedHoldUntil.addingTimeInterval(0.001),
                state: &state
            ) == .published("나는 전체 문장을 듣고 있어요")
        )
        #expect(state.visibleText == "나는 전체 문장을 듣고 있어요")
        #expect(state.pendingRewriteText == nil)
        #expect(state.rewriteHoldUntil == nil)
    }

    @Test
    func finalOrStoppedStateFlushesLatestTextImmediately() {
        var state = CaptionDisplayUpdatePolicy.State(visibleText: "I")
        let rewriteAt = start.addingTimeInterval(0.02)

        #expect(
            policy.receive("나", at: rewriteAt, canHoldRewrite: true, state: &state)
                == .held(until: rewriteAt.addingTimeInterval(0.28))
        )

        #expect(
            policy.receive(
                "나는 지금 전체 문장을 듣고 있어요",
                at: rewriteAt.addingTimeInterval(0.04),
                canHoldRewrite: false,
                state: &state
            ) == .published("나는 지금 전체 문장을 듣고 있어요")
        )
        #expect(state.visibleText == "나는 지금 전체 문장을 듣고 있어요")
        #expect(state.pendingRewriteText == nil)
        #expect(state.rewriteHoldUntil == nil)
    }

    @Test
    func candidateReturningToVisibleTextClearsStalePendingRewrite() {
        var state = CaptionDisplayUpdatePolicy.State(visibleText: "I")
        let rewriteAt = start.addingTimeInterval(0.02)

        #expect(
            policy.receive("나", at: rewriteAt, canHoldRewrite: true, state: &state)
                == .held(until: rewriteAt.addingTimeInterval(0.28))
        )

        #expect(
            policy.receive("I", at: rewriteAt.addingTimeInterval(0.03), canHoldRewrite: true, state: &state)
                == .unchanged
        )
        #expect(state.visibleText == "I")
        #expect(state.pendingRewriteText == nil)
        #expect(state.rewriteHoldUntil == nil)
    }
}
