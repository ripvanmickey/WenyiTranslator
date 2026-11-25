import SwiftUI

struct CloudflareSettingsView: View {
    @Bindable var session: TranslationSessionStore
    @State private var account = ""
    @State private var model = CloudflareConfiguration.defaultModel
    @State private var customModel = ""
    @State private var consent = false
    @State private var message = ""
    @State private var testing = false
    @State private var testTask: Task<Void, Never>?
    private var locked: Bool { session.isRunning || session.isStarting || testing }
    private var configuration: CloudflareConfiguration {
        .init(accountID: account, modelID: model == "custom" ? customModel : model, allowsTextSharing: consent)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Account ID").font(.caption.weight(.medium))
            TextField(AppText.ui("32 位 Cloudflare 账号 ID", "32-character Cloudflare Account ID", "32 桁の Cloudflare Account ID"), text: $account)
                .textFieldStyle(.roundedBorder).accessibilityIdentifier("cloudflareAccountID")
            Text(AppText.ui("翻译模型", "Translation Model", "翻訳モデル")).font(.caption.weight(.medium))
            Picker(AppText.ui("模型", "Model", "モデル"), selection: $model) {
                Text("Llama 3.1 8B · Fast").tag(CloudflareConfiguration.models[0])
                Text("Llama 3.3 70B · Fast").tag(CloudflareConfiguration.models[1])
                Text(AppText.ui("自定义模型 ID", "Custom model ID", "カスタムモデル ID")).tag("custom")
            }.pickerStyle(.menu).labelsHidden().frame(maxWidth: 360, alignment: .leading)
                .accessibilityIdentifier("cloudflareModelPicker")
            if model == "custom" {
                TextField("@cf/…", text: $customModel).textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("cloudflareCustomModel")
            }
            Toggle(AppText.ui("允许将字幕文字发送到 Cloudflare", "Allow sending caption text to Cloudflare", "字幕テキストの Cloudflare への送信を許可"), isOn: $consent)
                .toggleStyle(.checkbox).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("cloudflareTextConsent")
            Text(CloudflareCopy.quota).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(AppText.ui("保存配置", "Save configuration", "設定を保存"), action: save)
                    .accessibilityIdentifier("cloudflareSaveConfiguration")
                Button(AppText.ui("测试翻译", "Test translation", "翻訳をテスト"), action: test)
                    .disabled(!session.hasCloudflareAPIKey || !consent)
                    .accessibilityIdentifier("cloudflareTestTranslation")
                if testing { ProgressView().controlSize(.small) }
            }
            Text(AppText.ui("测试会发送固定的 Hello 文本，并消耗少量 API 用量。", "Testing sends the fixed text Hello and uses a small amount of API quota.", "テストでは固定文 Hello を送信し、少量の API 利用枠を消費します。"))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !message.isEmpty { Text(message).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
        }
        .disabled(locked)
        .onAppear {
            let config = session.localTranslation.cloudflareConfiguration
            account = config.accountID; consent = config.allowsTextSharing
            if CloudflareConfiguration.models.contains(config.modelID) { model = config.modelID }
            else { model = "custom"; customModel = config.modelID }
        }
        .onDisappear { testTask?.cancel(); testTask = nil }
    }
    private func save() {
        guard !locked else { return }
        do {
            var candidate = configuration; candidate.allowsTextSharing = true
            let validated = try candidate.validated()
            var saved = session.localTranslation
            saved.cloudflareAccountID = validated.accountID
            saved.cloudflareModelID = validated.modelID
            saved.cloudflareTextSharingAllowed = consent
            session.localTranslation = saved
            account = validated.accountID
            message = AppText.ui("Cloudflare 配置已保存。API Token 请在上方单独保存。", "Cloudflare configuration saved. Save the API Token separately above.", "Cloudflare 設定を保存しました。API Token は上で別途保存してください。")
        } catch { message = error.localizedDescription }
    }
    private func test() {
        guard !locked else { return }
        let config: CloudflareConfiguration
        do { config = try configuration.validated() } catch { message = error.localizedDescription; return }
        testing = true; message = ""
        testTask = Task {
            defer { testing = false }
            do {
                let key = try CloudflareAPIKeyStore.readAPIKey(retryAfterFailure: true)
                let result = try await CloudflareTranslationService.shared.translate("Hello", source: "en-US", target: "zh-CN", configuration: config, key: key)
                try Task.checkCancellation()
                message = AppText.ui("测试译文：", "Test translation: ", "テスト訳文：") + result
            } catch is CancellationError { }
            catch { message = error.localizedDescription }
        }
    }
}
