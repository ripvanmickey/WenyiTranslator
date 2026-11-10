import Foundation
@main struct Checks {
 static func main() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent("whisper-model-check-" + UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  let folder = root.appendingPathComponent("openai_whisper-base")
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  try Data("{\"d_model\":512}".utf8).write(to: folder.appendingPathComponent("config.json"))
  precondition(!WhisperModelFiles.isUsable(folder: folder, model: "base"))
  for component in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
   for file in ["coremldata.bin", "model.mil", "weights/weight.bin"] {
    let url = folder.appendingPathComponent(component + ".mlmodelc/" + file)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data([1]).write(to: url)
   }
  }
  precondition(WhisperModelFiles.isUsable(folder: folder, model: "base"))
  precondition(!WhisperModelFiles.isUsable(folder: folder, model: "small"))
  try Data().write(to: folder.appendingPathComponent("MelSpectrogram.mlmodelc/coremldata.bin"))
  precondition(!WhisperModelFiles.isUsable(folder: folder, model: "base"))
  print("PASS model identity mismatch, incomplete components, zero-byte files, complete file structure")
 }
}
