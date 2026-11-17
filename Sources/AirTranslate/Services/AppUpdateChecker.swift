import Foundation
import Observation
import UserNotifications

struct AppUpdateRelease: Decodable, Equatable {
    let tagName: String
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]

    struct Asset: Decodable, Equatable {
        let name: String
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case draft, prerelease, assets
    }

    static let releasesURL = URL(string: "https://github.com/ripvanmickey/WenyiTranslator/releases")!

    func update(for installed: RunningAppVersion, on os: OperatingSystemVersion) -> AppUpdate? {
        let version = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
        guard !draft, !prerelease,
              let releaseVersion = Self.versionComponents(version),
              let installedVersion = installed.version.flatMap(Self.versionComponents) else { return nil }

        let prefix = "Wenyi-\(version)-"
        let suffix = "-arm64.dmg"
        let compatibleAssets = assets.compactMap { asset -> (build: Int, name: String)? in
            guard asset.name.hasPrefix(prefix), asset.name.hasSuffix(suffix) else { return nil }
            let fields = asset.name.dropFirst(prefix.count).dropLast(suffix.count).components(separatedBy: "-macOS")
            guard fields.count == 2, let build = Int(fields[0]), build > 0,
                  let minimumOS = Self.versionComponents(fields[1]),
                  ![os.majorVersion, os.minorVersion, os.patchVersion].lexicographicallyPrecedes(minimumOS) else { return nil }
            return (build, asset.name)
        }
        guard let asset = compatibleAssets.max(by: { $0.build < $1.build }) else { return nil }

        let isNewerVersion = installedVersion.lexicographicallyPrecedes(releaseVersion)
        let isNewerBuild = installedVersion == releaseVersion && installed.build.flatMap(Int.init).map { $0 < asset.build } == true
        guard isNewerVersion || isNewerBuild else { return nil }
        return AppUpdate(version: version, build: asset.build, tagName: tagName, assetName: asset.name)
    }

    private static func versionComponents(_ value: String) -> [Int]? {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }) else { return nil }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == parts.count else { return nil }
        return numbers + Array(repeating: 0, count: 3 - numbers.count)
    }
}

struct AppUpdate: Equatable {
    let version: String
    let build: Int
    let tagName: String
    let assetName: String

    var summary: String { "\(version) (\(build))" }
    var downloadURL: URL { AppUpdateRelease.releasesURL.appending(path: "download").appending(path: tagName).appending(path: assetName) }
}

@MainActor
@Observable
final class AppUpdateChecker {
    static let shared = AppUpdateChecker()
    nonisolated static let notificationID = "wenyi.app-update.available"
    nonisolated static let notificationTagKey = "releaseTag"
    nonisolated static let notificationAssetKey = "releaseAsset"
    private static let endpoint = URL(string: "https://api.github.com/repos/ripvanmickey/WenyiTranslator/releases/latest")!

    enum Status {
        case idle, checking, upToDate, available, failed
    }

    private enum Key {
        static let notifications = "appUpdateNotificationsEnabled"
        static let lastNotified = "appUpdateLastNotifiedVersion"
    }

    private let defaults = UserDefaults.standard
    private var lastAttempt: Date?
    private(set) var status: Status = .idle
    private(set) var availableUpdate: AppUpdate?
    private(set) var notificationsEnabled = UserDefaults.standard.bool(forKey: Key.notifications)
    private(set) var isChangingNotificationPreference = false
    private(set) var notificationPermissionUnavailable = false

    func checkIfDue() async {
        if let lastAttempt, (0..<86_400).contains(Date().timeIntervalSince(lastAttempt)) { return }
        await check(manual: false)
    }

    func check(manual: Bool = true) async {
        guard status != .checking else { return }
        let previousStatus = status
        status = .checking
        lastAttempt = .now

        do {
            var request = URLRequest(url: Self.endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let release = try JSONDecoder().decode(AppUpdateRelease.self, from: data)
            availableUpdate = release.update(for: .current(), on: ProcessInfo.processInfo.operatingSystemVersion)
            status = availableUpdate == nil ? .upToDate : .available
            await notifyIfNeeded()
        } catch {
            status = manual ? .failed : previousStatus
        }
    }

    func setNotificationsEnabled(_ enabled: Bool) async {
        guard !isChangingNotificationPreference else { return }
        guard Bundle.main.bundleIdentifier != nil else {
            notificationPermissionUnavailable = true
            return
        }
        isChangingNotificationPreference = true
        defer { isChangingNotificationPreference = false }
        let center = UNUserNotificationCenter.current()

        if enabled {
            notificationsEnabled = (try? await center.requestAuthorization(options: [.alert, .sound])) == true
            notificationPermissionUnavailable = !notificationsEnabled
        } else {
            notificationsEnabled = false
            notificationPermissionUnavailable = false
            center.removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
            center.removeDeliveredNotifications(withIdentifiers: [Self.notificationID])
        }

        defaults.set(notificationsEnabled, forKey: Key.notifications)
        if notificationsEnabled { await notifyIfNeeded() }
    }

    private func notifyIfNeeded() async {
        guard Bundle.main.bundleIdentifier != nil, notificationsEnabled, let update = availableUpdate,
              defaults.string(forKey: Key.lastNotified) != update.summary else { return }

        let center = UNUserNotificationCenter.current()
        let authorization = await center.notificationSettings().authorizationStatus
        guard notificationsEnabled, availableUpdate == update,
              authorization == .authorized || authorization == .provisional,
              defaults.string(forKey: Key.lastNotified) != update.summary else { return }

        let content = UNMutableNotificationContent()
        content.title = AppUpdateCopy.available
        content.body = AppUpdateCopy.versionAvailable(update.summary)
        content.sound = .default
        content.userInfo = [Self.notificationTagKey: update.tagName, Self.notificationAssetKey: update.assetName]
        do {
            defaults.set(update.summary, forKey: Key.lastNotified)
            try await center.add(UNNotificationRequest(identifier: Self.notificationID, content: content, trigger: nil))
        } catch {
            if defaults.string(forKey: Key.lastNotified) == update.summary {
                defaults.removeObject(forKey: Key.lastNotified)
            }
        }
    }
}
