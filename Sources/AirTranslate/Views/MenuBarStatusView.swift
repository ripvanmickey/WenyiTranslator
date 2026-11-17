import SwiftUI

struct MenuBarStatusView: View {
    @Bindable var session: TranslationSessionStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(session.captureControlState.statusTitle(statusMessage: session.statusMessage))
        Divider()

        Button(capturePhase.actionTitle, systemImage: capturePhase.actionSystemImage) {
            if capturePhase == .idle {
                session.start()
                if session.captureStartFailureMessage != nil {
                    CaptionControlActions.showMainWindow(using: openWindow)
                }
            } else {
                session.stop()
            }
        }
        .disabled(!session.captureControlState.canToggleCapture)

        if session.isRunning {
            Button(session.isPaused ? AppText.resume : AppText.pause,
                   systemImage: session.isPaused ? "play.fill" : "pause.fill") {
                session.isPaused ? session.resume() : session.pause()
            }
            .disabled(!session.captureControlState.canTogglePause)
        }

        Button(session.isFloatingCaptionPresentationActive ? AppText.hideFloatingCaptions : AppText.showFloatingCaptions,
               systemImage: "captions.bubble") {
            if FloatingCaptionWindowController.isOpen {
                FloatingCaptionWindowController.close()
            } else {
                FloatingCaptionWindowController.open(session: session, preview: true)
            }
        }

        Button(AppText.showCaptionsOnly, systemImage: "captions.bubble.fill") {
            CaptionControlActions.showCaptionsOnly(session: session, using: openWindow)
        }
        .disabled(capturePhase == .finishing)

        Button(AppText.openMainWindow, systemImage: "macwindow") {
            CaptionControlActions.showMainWindow(using: openWindow)
        }

        Divider()

        CaptionDisplayModePicker(session: session)
            .pickerStyle(.menu)

        Menu(AppText.captionStyle, systemImage: "slider.horizontal.3") {
            Text("\(AppText.size): \(Int(session.floatingCaptionPrimaryPointSize)) pt")
            CaptionTextSizeButtons(session: session)
            Menu(AppText.floatingTextSize) {
                ForEach(FloatingCaptionTextSize.allCases) { size in
                    Button(size.title) {
                        session.selectFloatingCaptionTextSizePreset(size)
                    }
                }
            }

            Picker(AppText.lines, selection: $session.floatingCaptionLineCount) {
                ForEach(FloatingCaptionLineCount.allCases) { count in
                    Text(count.title).tag(count)
                }
            }

            Picker(AppText.stability, selection: $session.floatingCaptionStability) {
                ForEach(FloatingCaptionStability.allCases) { stability in
                    Text(stability.title).tag(stability)
                }
            }
        }

        Divider()

        SettingsLink {
            Label(AppText.settings, systemImage: "gearshape")
        }

        Button(AppText.quit, systemImage: "power") {
            NSApp.terminate(nil)
        }
    }

    private var capturePhase: MenuBarCapturePhase {
        session.captureControlState.phase
    }
}

enum MenuBarCapturePhase: Equatable {
    case idle
    case starting
    case running
    case paused
    case finishing
    case reconnecting

    init(
        isRunning: Bool,
        isStarting: Bool,
        isPaused: Bool,
        isFinishing: Bool = false,
        isReconnecting: Bool = false
    ) {
        if isStarting {
            self = .starting
        } else if isRunning {
            if isFinishing {
                self = .finishing
            } else if isReconnecting {
                self = .reconnecting
            } else {
                self = isPaused ? .paused : .running
            }
        } else {
            self = .idle
        }
    }

    var actionSystemImage: String {
        switch self {
        case .idle:
            "play.fill"
        case .starting, .reconnecting:
            "xmark"
        case .running, .paused:
            "stop.fill"
        case .finishing:
            "hourglass"
        }
    }

    var actionTitle: String {
        switch self {
        case .idle:
            AppText.start
        case .starting, .reconnecting:
            AppText.cancel
        case .running, .paused:
            AppText.stop
        case .finishing:
            AppText.finishingCapture
        }
    }

    var showsProgress: Bool {
        self == .starting || self == .finishing || self == .reconnecting
    }
}
