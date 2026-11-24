import AppKit
import Foundation
import AirTranslateCore

enum VideoPlaybackBrowser: String, CaseIterable, Identifiable, Sendable {
    case chrome, safari
    var id: String { rawValue }
    var title: String { self == .chrome ? "Chrome" : "Safari" }
    var bundleID: String { self == .chrome ? "com.google.Chrome" : "com.apple.Safari" }
}

struct VideoPlaybackSnapshot: Decodable, Sendable {
    let url: String?
    let time: Double?
    let paused: Bool?
    let rate: Double?
    let ad: Bool?
    let unsupported: Bool?
}

/// Read-only automation of the browser explicitly selected by the user.
/// Each poll inspects only the front tab, and returns data only for youtube.com video pages.
actor VideoBrowserConnection {
    private static let probe = """
    (()=>{
      if(!['www.youtube.com','youtube.com','m.youtube.com'].includes(location.hostname))return JSON.stringify({unsupported:true});
      const v=document.querySelector('video.html5-main-video')||document.querySelector('video');
      if(!v)return JSON.stringify({unsupported:true});
      return JSON.stringify({url:location.href,time:v.currentTime,paused:v.paused,rate:v.playbackRate,
        ad:!!document.querySelector('.html5-video-player.ad-showing')});
    })()
    """

    func read(_ browser: VideoPlaybackBrowser, initial: Bool = false) throws -> VideoPlaybackSnapshot {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleID).isEmpty else {
            throw VideoPreloadProblem(message: "请先在 \(browser.title) 打开 YouTube 视频。")
        }
        let javascript = Self.probe.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: " ")
        let command = browser == .chrome
            ? "execute active tab of front window javascript \"\(javascript)\""
            : "do JavaScript \"\(javascript)\" in front document"
        let source = """
        with timeout of \(initial ? 60 : 3) seconds
          tell application id "\(browser.bundleID)"
            return \(command)
          end tell
        end timeout
        """
        guard let script = NSAppleScript(source: source) else {
            throw VideoPreloadProblem(message: "无法创建浏览器同步连接。")
        }
        var details: NSDictionary?
        let descriptor = script.executeAndReturnError(&details)
        if let details {
            let code = details[NSAppleScript.errorNumber] as? Int ?? 0
            if code == -1743 || code == -10004 {
                throw VideoPreloadProblem(message: "请在系统设置 → 隐私与安全性 → 自动化中，允许文译访问 \(browser.title)。")
            }
            let explanation = details[NSAppleScript.errorMessage] as? String ?? "浏览器未返回播放位置"
            throw VideoPreloadProblem(message: "连接 \(browser.title) 失败（\(code)）：\(explanation)")
        }
        guard let raw = descriptor.stringValue?.data(using: .utf8), raw.count < 16_384,
              let snapshot = try? JSONDecoder().decode(VideoPlaybackSnapshot.self, from: raw),
              snapshot.unsupported != true, let url = snapshot.url,
              (try? YouTubeVideoReference(url)) != nil, let time = snapshot.time,
              time.isFinite, time >= 0, let rate = snapshot.rate, rate.isFinite, rate > 0 else {
            throw VideoPreloadProblem(message: "请将要同步的 YouTube 视频切换到浏览器当前标签页。")
        }
        return snapshot
    }
}
