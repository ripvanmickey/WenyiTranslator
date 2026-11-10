import Foundation

/// Keeps selection, on-disk identity and completeness separate from UI messages.
enum WhisperModelFiles {
    static func defaultFolder(base: URL, model: String) -> URL {
        base.appendingPathComponent("models/argmaxinc/whisperkit-coreml/openai_whisper-" + model)
    }
    static func identity(folder: URL) -> String? {
        if let data = try? Data(contentsOf: folder.appendingPathComponent("config.json")),
           let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let dimension = config["d_model"] as? Int {
            return [384: "tiny", 512: "base", 768: "small"][dimension]
        }
        return ["tiny", "base", "small"].first { folder.lastPathComponent == "openai_whisper-" + $0 }
    }
    static func isUsable(folder: URL, model: String) -> Bool {
        guard identity(folder: folder) == model else { return false }
        for component in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            for file in ["coremldata.bin", "model.mil", "weights/weight.bin"] {
                let url = folder.appendingPathComponent(component + ".mlmodelc/" + file)
                guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                      values.isRegularFile == true, (values.fileSize ?? 0) > 0 else { return false }
            }
        }
        return true
    }
}
