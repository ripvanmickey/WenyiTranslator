import Testing
@testable import AirTranslate

@Suite
struct SessionConfigurationUIStateTests {
    @Test
    func menuBarStartingPhaseOffersCancellationAndReportsCurrentStatus() {
        let state = CaptureControlState(
            isRunning: false,
            isStarting: true,
            isPaused: false
        )
        let status = AppText.connectingGeminiLiveTranslation

        let phase = state.phase
        #expect(phase == .starting)
        #expect(phase.actionSystemImage == "xmark")
        #expect(phase.actionTitle == AppText.cancel)
        #expect(state.statusTitle(statusMessage: status) == status)
    }

    @Test
    func menuBarIdleAndRunningPhasesPreserveStartStopActions() {
        let idle = MenuBarCapturePhase(
            isRunning: false,
            isStarting: false,
            isPaused: false
        )
        let running = MenuBarCapturePhase(
            isRunning: true,
            isStarting: false,
            isPaused: false
        )

        #expect(idle.actionTitle == AppText.start)
        #expect(idle.actionSystemImage == "play.fill")
        #expect(running.actionTitle == AppText.stop)
        #expect(running.actionSystemImage == "stop.fill")

        let pausedState = CaptureControlState(
            isRunning: true,
            isStarting: false,
            isPaused: true
        )

        let paused = pausedState.phase
        #expect(paused == .paused)
        #expect(paused.actionTitle == AppText.stop)
        #expect(paused.actionSystemImage == "stop.fill")
        #expect(pausedState.statusTitle(statusMessage: "ignored") == AppText.paused)
    }

    @Test
    func sidebarConfigurationIsLockedForRunningOrStartingSessions() {
        #expect(
            SidebarSessionConfigurationAccess.isLocked(
                isRunning: false,
                isStarting: false
            ) == false
        )
        #expect(
            SidebarSessionConfigurationAccess.isLocked(
                isRunning: true,
                isStarting: false
            )
        )
        #expect(
            SidebarSessionConfigurationAccess.isLocked(
                isRunning: false,
                isStarting: true
            )
        )
        #expect(
            SidebarSessionConfigurationAccess.isLocked(
                isRunning: true,
                isStarting: true
            )
        )
    }

    @Test
    func sidebarSegmentedControlsUsePassiveSummaryWhileConfigurationIsLocked() {
        #expect(
            SidebarSessionConfigurationAccess.segmentedControlPresentation(
                isRunning: false,
                isStarting: false
            ) == .picker
        )
        #expect(
            SidebarSessionConfigurationAccess.segmentedControlPresentation(
                isRunning: false,
                isStarting: true
            ) == .lockedSummary
        )
        #expect(
            SidebarSessionConfigurationAccess.segmentedControlPresentation(
                isRunning: true,
                isStarting: false
            ) == .lockedSummary
        )
    }

    @Test
    func settingsSegmentedControlsBlockPointerAndAccessibilityInteractionWithoutChangingControlEnabledState() {
        #expect(
            SettingsSegmentedControlAccess.allowsHitTesting(
                isRunning: false,
                isStarting: false
            )
        )
        #expect(
            !SettingsSegmentedControlAccess.allowsHitTesting(
                isRunning: false,
                isStarting: true
            )
        )
        #expect(
            !SettingsSegmentedControlAccess.allowsHitTesting(
                isRunning: true,
                isStarting: false
            )
        )
        #expect(
            !SettingsSegmentedControlAccess.allowsHitTesting(
                isRunning: false,
                isStarting: false,
                isOtherwiseAvailable: false
            )
        )
    }
}
