# 文译 Wenyi 1.16.3（构建 1246）

- 修复 OpenAI 模型无法使用的问题：调整实时语音翻译及转写的连接配置，完善连接失败反馈。
- 修复 OpenAI 密钥授权弹窗反复出现的问题；开始聆听前读取并在内存中复用密钥，授权失败后等待用户主动重试。
- API 密钥设置支持查看和隐藏已保存的密钥，替换失败时保留原密钥。
- OpenAI 支持本地 ASR + GPT-4.1 mini 翻译，只向 OpenAI 发送字幕文字。
- OpenAI 实时翻译增加字幕分段，保存记录时保留段落及已开启的时间戳。

适用于 Apple Silicon（M1 及以上），最低 macOS 14.0，支持 macOS 27。
下载 DMG 后将「文译」拖到「应用程序」。应用采用临时签名，尚未经过 Apple 公证。
本次完成本地构建、请求配置与密钥缓存专项检查、安装包签名和兼容性检查；不同 OpenAI 账号的权限、额度及实际网络环境仍需用户验证。

## English

Fix OpenAI model connection/configuration issues and repeated Keychain authorization prompts. Saved API keys can be revealed on demand. OpenAI translation can use on-device ASR with GPT-4.1 mini, sending caption text only. Realtime translations now retain caption paragraphs in saved transcripts.

Requires Apple Silicon and macOS 14.0 or later, including macOS 27. Ad hoc signed; not Apple-notarized. Local checks passed; live account permissions, quota and network behavior require user verification.

## 日本語

OpenAI モデルの接続・設定に関する不具合と、キーチェーンの認証ダイアログが繰り返し表示される問題を修正しました。保存済み API キーの表示切替、ローカル音声認識と GPT-4.1 mini によるテキスト翻訳、リアルタイム翻訳の段落分割に対応しました。

Apple Silicon、macOS 14.0 以降（macOS 27 を含む）に対応。Apple の公証は未取得です。ローカル検証済みですが、各アカウントの権限・利用枠・ネットワーク環境での動作確認は別途必要です。
