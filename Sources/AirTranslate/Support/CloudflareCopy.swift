import Foundation

enum CloudflareCopy {
    static var title: String { "Cloudflare Workers AI" }
    static var detail: String { AppText.ui("语音在本机识别，只将字幕文字发送到 Cloudflare 翻译。使用 Cloudflare Account ID 和 API Token，与 Meta 官方接口独立。", "Recognize speech on this Mac and send only caption text to Cloudflare. Use a Cloudflare Account ID and API Token, separate from Meta's API.", "音声はこの Mac で認識し、字幕テキストのみを Cloudflare に送信します。Meta の API とは別の Account ID と API Token を使用します。") }
    static var quota: String { AppText.ui("有每日免费额度，部分模型需付费；额度取决于模型和账号。不会自动切换备用模型或重试收费请求。", "Daily free allocation is available; some models require payment. Usage depends on your model and account. No automatic fallback or paid-request retry.", "毎日の無料利用枠がありますが、一部モデルは有料です。利用量はモデルとアカウントに依存します。代替モデルへの自動切替や有料リクエストの自動再試行はしません。") }
    static var configure: String { AppText.ui("配置 Cloudflare", "Configure Cloudflare", "Cloudflare を設定") }
    static var notTested: String { AppText.ui("尚未使用真实账号验证，需自行确认模型权限和额度。", "Not verified with a live account. Check model access and quota.", "実アカウントで未検証です。モデル権限と利用枠を確認してください。") }
}
