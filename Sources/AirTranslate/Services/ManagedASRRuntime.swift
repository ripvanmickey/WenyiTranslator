import Foundation

/// App-owned interpreter + per-user model data. No build-machine runtime or trial folder is needed.
enum ManagedASRRuntime {
    static var resources: URL { Bundle.main.resourceURL! }
    static var runtime: URL { resources.appendingPathComponent("ASRRuntime") }
    static var data: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Wenyi/ASR", isDirectory: true)
    }
    static var available: Bool { FileManager.default.isExecutableFile(atPath: runtime.appendingPathComponent("bin/python3.12").path) }
    static func environment(engine: String, online: Bool = false, resourceRoot: URL? = nil, modelData: URL? = nil) -> [String: String] {
        let resources = resourceRoot ?? Self.resources
        let runtime = resources.appendingPathComponent("ASRRuntime")
        let data = modelData ?? Self.data
        // Deliberately do not inherit Python paths, user-site packages or Hugging Face tokens.
        let profile = engine == "granite" || online ? "granite" : engine == "qwen" ? "qwen" : "legacy"
        var paths = [runtime.appendingPathComponent("packages/" + profile).path]
        if profile == "qwen" { paths.append(runtime.appendingPathComponent("packages/legacy").path) }
        paths.append(resources.appendingPathComponent("ASRProject").path)
        return ["HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8",
                "PYTHONHOME": runtime.path, "PYTHONPATH": paths.joined(separator: ":"),
                "PYTHONNOUSERSITE": "1", "PYTHONDONTWRITEBYTECODE": "1", "PYTHONUNBUFFERED": "1",
                "HF_HOME": data.appendingPathComponent("cache").path, "HF_HUB_OFFLINE": online ? "0" : "1",
                "WENYI_MANAGED_ASR": "1", "WENYI_ASR_RESOURCES": resources.path,
                "SSL_CERT_FILE": runtime.appendingPathComponent("cacert.pem").path]
    }
    static func modelID(granite: Bool, qwen: String) -> String {
        granite ? "granite" : qwen.isEmpty ? "nemotron" : qwen.contains("1.7B") ? "qwen17" : "qwen06"
    }
    static func validate(_ id: String, resourceRoot: URL? = nil, modelData: URL? = nil) throws {
        let runtime = (resourceRoot ?? resources).appendingPathComponent("ASRRuntime")
        let data = modelData ?? Self.data
        guard FileManager.default.isExecutableFile(atPath: runtime.appendingPathComponent("bin/python3.12").path) else { throw WhisperKitSpeechTranscriber.Problem(message: "应用缺少内置识别组件，请重新安装完整版本。") }
        let ids = ["granite", "multitalker"].contains(id) ? [id] : [id, "vad"]
        for key in ids {
            let base = data.appendingPathComponent("models/" + key)
            guard FileManager.default.fileExists(atPath: base.appendingPathComponent("ready.json").path),
                  FileManager.default.fileExists(atPath: base.appendingPathComponent(key == "multitalker" ? "files/multitalker-parakeet-streaming-0.6b-v1-Q8_0.gguf" : "files/config.json").path) else {
                throw WhisperKitSpeechTranscriber.Problem(message: "请先在语音识别设置的模型管理中下载或导入所选模型。")
            }
        }
    }
}
