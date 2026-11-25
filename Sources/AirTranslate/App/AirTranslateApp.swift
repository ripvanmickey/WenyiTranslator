import AppKit
import SwiftUI
import UserNotifications

@main
struct AirTranslateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var session = TranslationSessionStore()
    @State private var videoSubtitles = VideoSubtitlePreloadStore()
    @State private var isMediaInputSelected = false

    init() {
        appDelegate.session = session
    }

    var body: some Scene {
        WindowGroup("文译", id: AirTranslateWindowID.main) {
            ContentView(session: session, videoSubtitles: videoSubtitles, isMediaInputSelected: $isMediaInputSelected)
                .environment(\.locale, AppText.interfaceLocale)
                .frame(
                    minWidth: MediaWorkspaceLayout.minimumWindowWidth(media: isMediaInputSelected),
                    minHeight: AirTranslateDesign.mainWindowMinimumHeight
                )
                .tint(AirTranslateDesign.Palette.accent)
        }
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unifiedCompact(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {}
            CaptureCommands(session: session, videoSubtitles: videoSubtitles, isMediaInputSelected: $isMediaInputSelected)
            CaptionCommands(session: session)
        }

        WindowGroup(AppText.floatingCaptionModeChoiceTitle, id: AirTranslateWindowID.floatingCaptionModeChoice) {
            FloatingCaptionModeChoiceView(session: session)
                .environment(\.locale, AppText.interfaceLocale)
        }
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarStatusView(session: session)
                .environment(\.locale, AppText.interfaceLocale)
        } label: {
            Image(systemName: session.isFloatingCaptionPresentationActive ? "captions.bubble.fill" : "captions.bubble")
                .accessibilityLabel(session.isPaused ? AppText.menuBarPausedTitle : session.isRunning ? AppText.menuBarRunningTitle : AppText.menuBarTitle)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(session: session)
                .environment(\.locale, AppText.interfaceLocale)
                .tint(AirTranslateDesign.Palette.accent)
        }
    }
}

@MainActor
private struct CaptureCommands: Commands {
    @Bindable var session: TranslationSessionStore
    @Bindable var videoSubtitles: VideoSubtitlePreloadStore
    @Binding var isMediaInputSelected: Bool

    var body: some Commands {
        CommandMenu(AppText.capture) {
            Button(isMediaInputSelected ? videoSubtitles.mainActionTitle : session.captureControlState.phase.actionTitle) {
                if isMediaInputSelected {
                    videoSubtitles.performMainAction()
                } else if session.isRunning || session.isStarting {
                    session.stop()
                } else {
                    session.start()
                }
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(isMediaInputSelected ? !videoSubtitles.canPerformMainAction : !session.captureControlState.canToggleCapture)

            Button(session.isPaused ? AppText.resume : AppText.pause) {
                session.isPaused ? session.resume() : session.pause()
            }
            .keyboardShortcut(.space, modifiers: [.command, .shift])
            .disabled(isMediaInputSelected || !session.captureControlState.canTogglePause)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var session: TranslationSessionStore?
    private var updateTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let appIcon = NSImage(named: "AppIcon") {
            NSApp.applicationIconImage = appIcon
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = self
        }
        updateTask = Task {
            while !Task.isCancelled {
                await AppUpdateChecker.shared.checkIfDue()
                do {
                    try await Task.sleep(for: .seconds(86_400))
                } catch {
                    break
                }
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Task { await AppUpdateChecker.shared.checkIfDue() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        updateTask?.cancel()
        session?.prepareForTermination()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        notification.request.identifier == AppUpdateChecker.notificationID ? [.banner, .list] : []
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.notification.request.identifier == AppUpdateChecker.notificationID,
              response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        let userInfo = response.notification.request.content.userInfo
        let tag = userInfo[AppUpdateChecker.notificationTagKey] as? String
        let asset = userInfo[AppUpdateChecker.notificationAssetKey] as? String
        await MainActor.run {
            if let tag, let asset {
                let release = AppUpdateRelease(tagName: tag, draft: false, prerelease: false, assets: [.init(name: asset)])
                if let update = release.update(for: .current(), on: ProcessInfo.processInfo.operatingSystemVersion) {
                    NSWorkspace.shared.open(update.downloadURL)
                }
            } else {
                NSWorkspace.shared.open(AppUpdateChecker.shared.availableUpdate?.downloadURL ?? AppUpdateRelease.releasesURL)
            }
        }
    }
}
