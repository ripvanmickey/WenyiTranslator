import Foundation
@main struct Checks {
    static func main() {
        func check(_ value: Bool, _ message: String) { precondition(value, message) }
        let sample = "でもあったしでホンマにあの曲できた瞬間風が吹いた感じがあったんですよね自分に背中にこれでいけるぞっていうなので１曲あげるとすれば"
        let sample2 = "君はどこ聴かないかなって思いますスピッツの冷めないっていうなんです2016年のはいに出した冷めないってアルバム曲があるんですけどあの曲"
        func words(_ text: String) -> String { text.filter { !$0.isWhitespace } }
        for text in [sample, sample2, String(repeating: "これは背景の話であの曲について続けて話していますけど", count: 5)] {
            let rendered = JapaneseCaptionLayout.format(text)
            check(rendered.contains("\n"), "unpunctuated Japanese must split immediately")
            check(words(rendered) == words(text), "all words, names and numbers preserved")
            check(!rendered.contains("。"), "do not invent sentence punctuation")
            check(JapaneseCaptionLayout.format(rendered) == rendered, "layout idempotence")
            print(rendered)
        }
        let raw = "これは大切な説明ですよね次の話に移りましょう"
        check(JapaneseCaptionLayout.format(raw).contains("ですよね\n"), "prefer explicit ending")
        check(JapaneseCaptionLayout.format("これは説明ですけどまだ話は続いています") == "これは説明ですけどまだ話は続いています", "conjunction not a sentence ending")
        let line = CaptionLine(sourceText: sample, translatedText: "我明白了。这是下一句。", createdAt: Date(), isFinal: true)
        check(line.sourceText == sample, "raw ASR unchanged")
        check(line.sourceDisplayText.contains("\n"), "shared CaptionLine path applies layout")
        check(line.translatedDisplayText == "我明白了。\n这是下一句。", "Chinese punctuation splits too")
        let english = CaptionLine(sourceText: "A natural English sentence.", translatedText: "A translation.", createdAt: Date(), isFinal: true)
        check(english.sourceDisplayText == english.sourceText, "English unchanged")
        let start = ProcessInfo.processInfo.systemUptime
        for _ in 0..<100 { _ = JapaneseCaptionLayout.format(sample2) }
        print("100 layouts: \((ProcessInfo.processInfo.systemUptime-start)*1000) ms")
        print("PASS screenshot samples, immediate reading breaks, word preservation, idempotence, shared display path and English regression")
    }
}
