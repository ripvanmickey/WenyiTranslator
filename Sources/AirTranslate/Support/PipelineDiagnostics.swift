import Foundation

/// 명시적으로 켠 로컬 성능 측정에 숫자만 기록한다. 전사·번역·키는 기록하지 않는다.
enum PipelineDiagnostics {
    static let isEnabled = ProcessInfo.processInfo.environment["AIRTRANSLATE_LATENCY_TRACE"] == "1"
    private static let outputLock = NSLock()

    static func record(_ stage: String, id: String = "", parentID: UUID? = nil, values: [String: Double] = [:]) {
        guard isEnabled else { return }
        var record: [String: Any] = values.filter { $0.value.isFinite }
        record["stage"] = stage
        record["uptime"] = ProcessInfo.processInfo.systemUptime
        if !id.isEmpty { record["id"] = id }
        if let parentID { record["parent_id"] = parentID.uuidString }
        guard let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return }
        outputLock.withLock {
            FileHandle.standardOutput.write(Data(("AIRTRANSLATE_LATENCY " + json + "\n").utf8))
        }
    }
}
