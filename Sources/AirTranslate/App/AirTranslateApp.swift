import AppKit
import SwiftUI

@main
struct AirTranslateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var session = TranslationSessionStore()

    init() {
        appDelegate.session = session
    }

    var body: some Scene {
        WindowGroup("文译", id: AirTranslateWindowID.main) {
            ContentView(session: session)
                .environment(\.locale, AppText.interfaceLocale)
                .frame(
                    minWidth: AirTranslateDesign.mainWindowMinimumWidth,
                    minHeight: AirTranslateDesign.mainWindowMinimumHeight
                )
                .tint(AirTranslateDesign.Palette.accent)
        }
        .windowToolbarStyle(.unifiedCompact(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {}
            CaptureCommands(session: session)
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

    var body: some Commands {
        CommandMenu(AppText.capture) {
            Button(session.captureControlState.phase.actionTitle) {
                if session.isRunning || session.isStarting {
                    session.stop()
                } else {
                    session.start()
                }
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(!session.captureControlState.canToggleCapture)

            Button(session.isPaused ? AppText.resume : AppText.pause) {
                session.isPaused ? session.resume() : session.pause()
            }
            .keyboardShortcut(.space, modifiers: [.command, .shift])
            .disabled(!session.captureControlState.canTogglePause)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var session: TranslationSessionStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let appIcon = NSImage(named: "AppIcon") {
            NSApp.applicationIconImage = appIcon
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        session?.prepareForTermination()
    }
}
