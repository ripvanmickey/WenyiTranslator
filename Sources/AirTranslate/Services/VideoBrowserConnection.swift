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
    var title: String? = nil
}

enum VideoPlaybackReadError: LocalizedError, Sendable {
    case temporary(String)
    case configuration(String)
    var errorDescription: String? {
        switch self { case .temporary(let text), .configuration(let text): text }
    }
    var canRetry: Bool {
        if case .temporary = self { return true }
        return false
    }
}

protocol VideoPlaybackReading: Sendable {
    func read(_ browser: VideoPlaybackBrowser, initial: Bool, videoID: String?) async throws -> VideoPlaybackSnapshot
    func setPaused(_ paused: Bool, browser: VideoPlaybackBrowser, videoID: String) async throws -> VideoPlaybackSnapshot
}

struct VideoBrowserTabSnapshot: Sendable {
    let url: String
    let title: String
}

protocol VideoBrowserTabReading: Sendable {
    func currentVideoTab(_ browser: VideoPlaybackBrowser) async throws -> VideoBrowserTabSnapshot?
}

/// Read the selected browser and control playback only on explicit user actions. After the first successful read, follow the
/// linked video rather than whichever window becomes frontmost during fullscreen.
actor VideoBrowserConnection: VideoPlaybackReading, VideoBrowserTabReading {
    private var chromeTabID: Int32?

    /// Discovery uses tab metadata only; it does not execute JavaScript or search other tabs.
    static func currentTabScriptSource(_ browser: VideoPlaybackBrowser) -> String {
        let selectedTab = browser == .chrome ? "active tab of front window" : "current tab of front window"
        let titleProperty = browser == .chrome ? "title" : "name"
        return """
        with timeout of 3 seconds
          tell application id "\(browser.bundleID)"
            if (count of windows) is 0 then return {}
            set selectedTab to \(selectedTab)
            set candidateURL to URL of selectedTab
            if candidateURL is missing value then return {}
            if not ((candidateURL starts with "https://www.youtube.com/") or (candidateURL starts with "https://youtube.com/") or (candidateURL starts with "https://m.youtube.com/") or (candidateURL starts with "https://youtu.be/") or (candidateURL starts with "https://www.youtu.be/")) then return {}
            return {candidateURL, \(titleProperty) of selectedTab}
          end tell
        end timeout
        """
    }

    func currentVideoTab(_ browser: VideoPlaybackBrowser) async throws -> VideoBrowserTabSnapshot? {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleID).isEmpty else { return nil }
        guard let script = NSAppleScript(source: Self.currentTabScriptSource(browser)) else {
            throw VideoPlaybackReadError.configuration(AppText.ui("无法读取浏览器标签页。", "Cannot read the browser tab.", "ブラウザのタブを読み取れません。"))
        }
        var details: NSDictionary?
        let descriptor = script.executeAndReturnError(&details)
        if let details {
            let code = details[NSAppleScript.errorNumber] as? Int ?? 0
            if code == -1743 || code == -10004 {
                throw VideoPlaybackReadError.configuration(AppText.ui("请在系统设置 → 隐私与安全性 → 自动化中，允许文译访问 \(browser.title)。", "Allow Wenyi to access \(browser.title) in System Settings → Privacy & Security → Automation.", "「システム設定 → プライバシーとセキュリティ → オートメーション」で、文訳から \(browser.title) へのアクセスを許可してください。"))
            }
            throw VideoPlaybackReadError.temporary(AppText.ui("暂时无法读取当前标签页，请保持 YouTube 视频标签页打开。", "The current tab is temporarily unavailable. Keep the YouTube video tab open.", "現在のタブを一時的に読み取れません。YouTube 動画のタブを開いたままにしてください。"))
        }
        guard let value = descriptor.atIndex(1)?.stringValue, value.utf8.count < 16_384,
              let video = try? YouTubeVideoReference(value) else { return nil }
        return .init(url: video.url.absoluteString, title: String((descriptor.atIndex(2)?.stringValue ?? "").prefix(512)))
    }

    private static let probe = """
    (()=>{
      if(!['www.youtube.com','youtube.com','m.youtube.com'].includes(location.hostname))return JSON.stringify({unsupported:true});
      const v=document.querySelector('video.html5-main-video')||document.querySelector('video');
      if(!v)return JSON.stringify({unsupported:true});
      return JSON.stringify({url:location.href,title:document.title.slice(0,512),time:v.currentTime,paused:v.paused,rate:v.playbackRate,
        ad:!!document.querySelector('.html5-video-player.ad-showing')});
    })()
    """

    // URL filtering reads tab metadata only. JavaScript runs solely in the linked
    // YouTube tab; unrelated pages are never probed.
    static func scriptSource(_ browser: VideoPlaybackBrowser, initial: Bool, videoID: String?, chromeTabID: Int32? = nil, paused: Bool? = nil) -> String {
        let validControlID = videoID.flatMap { $0.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) == nil ? nil : $0 }
        let action: String
        if let paused, let validControlID {
            action = """
            (()=>{
              const u=new URL(location.href);
              const id=u.searchParams.get('v')||u.pathname.split('/')[2];
              if(id!=='\(validControlID)')throw new Error('Linked video changed');
              if(!['www.youtube.com','youtube.com','m.youtube.com'].includes(u.hostname))throw new Error('Unsupported host');
              const v=document.querySelector('video.html5-main-video')||document.querySelector('video');
              if(!v)throw new Error('Video unavailable');
              \(paused ? "v.pause();" : "v.play().catch(()=>{});")
              return \(probe);
            })()
            """
        } else { action = probe }
        let javascript = action.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: " ")
        let validID = videoID.flatMap { $0.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) == nil ? nil : $0 }
        let selectTab: String
        if let validID, !initial {
            let passes = browser == .chrome && chromeTabID != nil ? [true, false] : [false]
            selectTab = passes.map { preferID in
                let idCheck = preferID ? " and (id of browserTab is \(chromeTabID!))" : ""
                return """
                if selectedTab is missing value then
                  repeat with browserWindow in windows
                    repeat with browserTab in tabs of browserWindow
                      try
                        set candidateURL to URL of browserTab
                        if (my matchesVideo(candidateURL, "\(validID)"))\(idCheck) then
                          set selectedTab to contents of browserTab
                          exit repeat
                        end if
                      end try
                    end repeat
                    if selectedTab is not missing value then exit repeat
                  end repeat
                end if
                """
            }.joined(separator: "\n")
        } else {
            selectTab = browser == .chrome
                ? "if (count of windows) > 0 then set selectedTab to active tab of front window"
                : "if (count of windows) > 0 then set selectedTab to current tab of front window"
        }
        let command = browser == .chrome
            ? "set playbackJSON to execute selectedTab javascript \"\(javascript)\"\nreturn {playbackJSON, id of selectedTab}"
            : "set playbackJSON to do JavaScript \"\(javascript)\" in selectedTab\nreturn {playbackJSON, 0}"
        return """
        on matchesVideo(candidateURL, videoID)
          if candidateURL is missing value then return false
          if not ((candidateURL starts with "https://www.youtube.com/") or (candidateURL starts with "https://youtube.com/") or (candidateURL starts with "https://m.youtube.com/")) then return false
          return ((candidateURL contains ("v=" & videoID)) or (candidateURL contains ("/shorts/" & videoID)) or (candidateURL contains ("/live/" & videoID)) or (candidateURL contains ("/embed/" & videoID)))
        end matchesVideo
        with timeout of \(initial ? 60 : 3) seconds
          tell application id "\(browser.bundleID)"
            set selectedTab to missing value
            \(selectTab)
            if selectedTab is missing value then error "Linked YouTube tab is temporarily unavailable" number -1728
            \(command)
          end tell
        end timeout
        """
    }

    func setPaused(_ paused: Bool, browser: VideoPlaybackBrowser, videoID: String) async throws -> VideoPlaybackSnapshot {
        guard videoID.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil else {
            throw VideoPlaybackReadError.configuration("Invalid linked video")
        }
        _ = try execute(browser, initial: false, videoID: videoID, paused: paused)
        try await Task.sleep(for: .milliseconds(200))
        let snapshot = try execute(browser, initial: false, videoID: videoID)
        guard snapshot.paused == paused else {
            throw VideoPlaybackReadError.temporary(AppText.ui("浏览器未完成播放操作，请在视频页面点击播放后重试。", "The browser could not change playback. Click play on the video page and try again.", "ブラウザで再生状態を変更できませんでした。動画ページで再生してから再試行してください。"))
        }
        return snapshot
    }

    func read(_ browser: VideoPlaybackBrowser, initial: Bool = false, videoID: String? = nil) async throws -> VideoPlaybackSnapshot {
        try execute(browser, initial: initial, videoID: videoID)
    }

    private func execute(_ browser: VideoPlaybackBrowser, initial: Bool, videoID: String?, paused: Bool? = nil) throws -> VideoPlaybackSnapshot {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleID).isEmpty else {
            throw VideoPlaybackReadError.configuration(AppText.ui("请先在 \(browser.title) 打开 YouTube 视频。", "Open a YouTube video in \(browser.title) first.", "先に \(browser.title) で YouTube 動画を開いてください。"))
        }
        if initial { chromeTabID = nil }
        guard let script = NSAppleScript(source: Self.scriptSource(browser, initial: initial, videoID: videoID, chromeTabID: chromeTabID, paused: paused)) else {
            throw VideoPlaybackReadError.configuration(AppText.ui("无法创建浏览器同步连接。", "Cannot create the browser sync connection.", "ブラウザ同期接続を作成できません。"))
        }
        var details: NSDictionary?
        let descriptor = script.executeAndReturnError(&details)
        if let details {
            let code = details[NSAppleScript.errorNumber] as? Int ?? 0
            if code == -1743 || code == -10004 {
                throw VideoPlaybackReadError.configuration(AppText.ui("请在系统设置 → 隐私与安全性 → 自动化中，允许文译访问 \(browser.title)。", "Allow Wenyi to access \(browser.title) in System Settings → Privacy & Security → Automation.", "「システム設定 → プライバシーとセキュリティ → オートメーション」で、文訳から \(browser.title) へのアクセスを許可してください。"))
            }
            let explanation = details[NSAppleScript.errorMessage] as? String ?? AppText.ui("浏览器未返回播放位置", "The browser did not return a playback position.", "ブラウザから再生位置を取得できませんでした。")
            let javascriptSettingsDisabled = explanation.localizedCaseInsensitiveContains("JavaScript")
                && ["turned off", "disabled", "not allowed", "allow javascript from apple events", "允许来自", "不允许", "未启用", "無効", "許可"].contains {
                    explanation.localizedCaseInsensitiveContains($0)
                }
            if javascriptSettingsDisabled {
                throw VideoPlaybackReadError.configuration(AppText.ui("连接 \(browser.title) 失败（\(code)）：\(explanation)", "Cannot connect to \(browser.title) (\(code)): \(explanation)", "\(browser.title) に接続できません（\(code)）：\(explanation)"))
            }
            throw VideoPlaybackReadError.temporary(AppText.ui("连接 \(browser.title) 暂时不可用（\(code)）：\(explanation)", "\(browser.title) connection temporarily unavailable (\(code)): \(explanation)", "\(browser.title) に一時的に接続できません（\(code)）：\(explanation)"))
        }
        guard let raw = descriptor.atIndex(1)?.stringValue?.data(using: .utf8), raw.count < 16_384,
              let snapshot = try? JSONDecoder().decode(VideoPlaybackSnapshot.self, from: raw),
              snapshot.unsupported != true, let url = snapshot.url,
              let video = try? YouTubeVideoReference(url), let time = snapshot.time,
              time.isFinite, time >= 0, let rate = snapshot.rate, rate.isFinite, rate > 0,
              videoID == nil || video.id == videoID else {
            throw VideoPlaybackReadError.temporary(AppText.ui("暂时无法读取关联视频，请保持原 YouTube 视频标签页打开。", "The linked video is temporarily unavailable. Keep its YouTube tab open.", "関連付けた動画を一時的に読み取れません。元の YouTube タブを開いたままにしてください。"))
        }
        if browser == .chrome { chromeTabID = descriptor.atIndex(2)?.int32Value }
        return snapshot
    }
}
