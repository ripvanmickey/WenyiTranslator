import AppKit
import SwiftUI

struct ContentView: View {
    @Bindable var session: TranslationSessionStore
    @Bindable var videoSubtitles: VideoSubtitlePreloadStore
    @Binding var isMediaInputSelected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openURL) private var openURL
    private let updates = AppUpdateChecker.shared
    @State private var isLibraryPresented = false
    @State private var isFloatingCaptionVisible = FloatingCaptionWindowController.isOpen
    @State private var isMainCaptionVisible = false
    @State private var captionViewport = CaptionFeedViewportState()

    private var captionWorkspace: some View {
        ZStack(alignment: .top) {
            AirTranslateDesign.Palette.canvas
                .ignoresSafeArea()

            // Keep the layout mounted when occlusion changes or the app is inactive.
            // Visibility notifications only gate accessibility announcements below.
            Group {
                if isMediaInputSelected {
                    MediaCaptionBoardView(model: videoSubtitles)
                } else {
                    VStack(spacing: 0) {
                        StageHeaderView(session: session)
                        CaptionBoardView(session: session, viewportState: $captionViewport)
                    }
                }

                VStack(spacing: AirTranslateDesign.Spacing.xs) {
                    if !isMediaInputSelected, let failureMessage = session.captureStartFailureMessage {
                        CaptureStartFailureView(
                            message: failureMessage,
                            recoveryAction: session.captureStartRecoveryAction,
                            recover: recoverFromCaptureStartFailure,
                            dismiss: session.dismissCaptureStartFailure
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if !isMediaInputSelected, let toastMessage = session.toastMessage {
                        ToastMessageView(message: toastMessage)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(.top, AirTranslateDesign.Spacing.sm)
                .padding(.horizontal, AirTranslateDesign.Spacing.lg)
            }
        }

    }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                captionWorkspace
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        Group {
                            ConsoleBarView(session: session, isMediaInputSelected: $isMediaInputSelected, media: videoSubtitles)
                                .padding(.horizontal, 24)
                                .padding(.top, isMediaInputSelected ? 18 : 8)
                                .padding(.bottom, isMediaInputSelected ? 24 : 16)
                        }
                    }
                    .frame(minWidth: MediaWorkspaceLayout.captionMinimumWidth, maxWidth: .infinity, maxHeight: .infinity)
                if isMediaInputSelected {
                    Divider()
                    VideoSubtitlePreloadView(model: videoSubtitles, session: session) {
                        isMediaInputSelected = false
                    }
                    .frame(width: MediaWorkspaceLayout.sidebarWidth(for: geometry.size.width))
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .toolbar { shortcutToolbar(sidebarWidth: isMediaInputSelected ? MediaWorkspaceLayout.sidebarWidth(for: geometry.size.width) + MediaWorkspaceLayout.dividerWidth : 0) }
        }
        .frame(minWidth: MediaWorkspaceLayout.minimumWindowWidth(media: isMediaInputSelected))
        .animation(reduceMotion ? nil : AirTranslateDesign.Motion.enter, value: isMediaInputSelected)
        .onChange(of: isMediaInputSelected) { _, selected in
            if !selected {
                videoSubtitles.disconnect()
                if videoSubtitles.overlayVisible { videoSubtitles.toggleOverlay() }
            }
        }
        .background {
            MediaWorkspaceWindowSizer(expanded: isMediaInputSelected, reduceMotion: reduceMotion)
                .allowsHitTesting(false).accessibilityHidden(true)
            MainCaptionWindowObserver(isCaptionVisible: $isMainCaptionVisible)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .controlSize(.regular)
        .sheet(isPresented: $isLibraryPresented) {
            TranscriptLibraryView(session: session)
        }
        .onAppear {
            syncFloatingCaptionVisibility()
        }
        .onReceive(NotificationCenter.default.publisher(for: FloatingCaptionWindowController.visibilityDidChangeNotification)) { _ in
            syncFloatingCaptionVisibility()
        }
        .animation(reduceMotion ? nil : AirTranslateDesign.Motion.state, value: session.toastSequence)
        .animation(reduceMotion ? nil : AirTranslateDesign.Motion.enter, value: session.toastMessage)
        .onChange(of: session.captureControlState.phase) { oldPhase, newPhase in
            // 시작 실패 배너의 알림과 중복하지 않고 준비·전환의 진입/완료만 알린다.
            guard isMainCaptionVisible, session.captureStartFailureMessage == nil,
                  oldPhase.showsProgress || newPhase.showsProgress else { return }
            AccessibilityNotification.Announcement(session.statusMessage).post()
        }
        .confirmationDialog(
            AppText.autoDetectionLanguageChangeTitle,
            isPresented: autoDetectionLanguageChangeBinding,
            titleVisibility: .visible
        ) {
            Button(AppText.startNewAutoDetectionSession) {
                session.confirmAutoDetectionLanguageChange()
            }

            Button(AppText.keepCurrentAutoDetectionLanguage, role: .cancel) {
                session.keepCurrentAutoDetectionLanguage()
            }
        } message: {
            if let languageChange = session.pendingAutoDetectionLanguageChange {
                Text(
                    AppText.autoDetectionLanguageChangeMessage(
                        current: languageChange.currentLanguage.localizedTitle,
                        detected: languageChange.detectedLanguage.localizedTitle,
                        target: languageChange.targetLanguage.localizedTitle
                    )
                )
            }
        }
    }

    private func recoverFromCaptureStartFailure(_ action: CaptureStartRecoveryAction) {
        switch action {
        case .apiKeys:
            session.requestAPIKeySettings()
            openSettings()
        case .generalSettings:
            session.requestGeneralSettings()
            openSettings()
        case .privacy(let pane):
            session.openPrivacySettings(pane)
        case .retry:
            session.start()
        }
    }

    @ToolbarContentBuilder
    private func shortcutToolbar(sidebarWidth: CGFloat) -> some ToolbarContent {
            ToolbarItemGroup(placement: .primaryAction) {
                if let update = updates.availableUpdate {
                    Button {
                        openURL(update.downloadURL)
                    } label: {
                        Image(systemName: "arrow.down.circle")
                    }
                    .help(AppUpdateCopy.versionAvailable(update.summary))
                    .accessibilityLabel(AppUpdateCopy.available)
                    .accessibilityIdentifier("wenyiUpdateAvailable")
                }

                Button {
                    isLibraryPresented = true
                } label: {
                    Image(systemName: "tray.full")
                }
                .help(AppText.manageSavedTranscripts)
                .accessibilityLabel(AppText.library)

                Button {
                    toggleFloatingCaptions()
                } label: {
                    Image(systemName: floatingCaptionsVisible ? "captions.bubble.fill" : "captions.bubble")
                }
                .help(AppText.floatingCaptions)
                .accessibilityLabel(AppText.floatingCaptions)
                .accessibilityValue(
                    floatingCaptionsVisible
                        ? AppText.floatingCaptionPowerOn
                        : AppText.floatingCaptionPowerOff
                )
                .accessibilityAddTraits(floatingCaptionsVisible ? .isSelected : [])
            }

            ToolbarItem(placement: .primaryAction) {
                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .help(AppText.configureTranslationSettings)
                .accessibilityLabel(AppText.translationSettings)
            }
        if sidebarWidth > 0 {
            if #available(macOS 26.0, *) {
                ToolbarItem(id: "mediaInspectorToolbarSpace", placement: .primaryAction) {
                    Color.clear.frame(width: sidebarWidth, height: 1)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
                .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(id: "mediaInspectorToolbarSpace", placement: .primaryAction) {
                    Color.clear.frame(width: sidebarWidth, height: 1)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
            }
        }
    }

    private var floatingCaptionsVisible: Bool {
        isMediaInputSelected ? videoSubtitles.overlayVisible : isFloatingCaptionVisible
    }

    private func toggleFloatingCaptions() {
        if isMediaInputSelected {
            videoSubtitles.toggleOverlay()
            return
        }
        CaptionControlActions.toggleVisibility(session: session, using: openWindow)
        syncFloatingCaptionVisibility()
    }

    private func syncFloatingCaptionVisibility() {
        isFloatingCaptionVisible = FloatingCaptionWindowController.isOpen
    }

    private var autoDetectionLanguageChangeBinding: Binding<Bool> {
        Binding(
            get: { session.pendingAutoDetectionLanguageChange != nil },
            set: { isPresented in
                if !isPresented {
                    session.keepCurrentAutoDetectionLanguage()
                }
            }
        )
    }
}

private struct CaptureStartFailureView: View {
    let message: String
    let recoveryAction: CaptureStartRecoveryAction?
    let recover: (CaptureStartRecoveryAction) -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: AirTranslateDesign.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AirTranslateDesign.Palette.warning)
                .accessibilityHidden(true)

            Text(message)
                .font(AirTranslateDesign.Typography.label.weight(.semibold))
                .foregroundStyle(AirTranslateDesign.Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)

            if let recoveryAction {
                Button(actionTitle(for: recoveryAction)) {
                    recover(recoveryAction)
                }
                .buttonStyle(.borderedProminent)
                .tint(AirTranslateDesign.Palette.accent)
                .controlSize(.small)
            }

            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppText.dismissStartFailure)
        }
        .padding(.horizontal, AirTranslateDesign.Spacing.md)
        .padding(.vertical, AirTranslateDesign.Spacing.sm)
        .frame(maxWidth: 680)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AirTranslateDesign.Radius.surface, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AirTranslateDesign.Radius.surface, style: .continuous)
                .strokeBorder(AirTranslateDesign.Palette.warning)
        }
        .shadow(
            color: AirTranslateDesign.Palette.shadow.opacity(AirTranslateDesign.Elevation.floatingOpacity),
            radius: AirTranslateDesign.Elevation.floatingRadius,
            y: AirTranslateDesign.Elevation.floatingY
        )
        .accessibilityElement(children: .contain)
        .onAppear {
            AccessibilityNotification.Announcement(message).post()
        }
        .onChange(of: message) { _, newValue in
            AccessibilityNotification.Announcement(newValue).post()
        }
    }

    private func actionTitle(for action: CaptureStartRecoveryAction) -> String {
        switch action {
        case .apiKeys: AppText.openAPIKeySettings
        case .generalSettings: NariCopy.chooseGAModel
        case .privacy: AppText.openPrivacySettings
        case .retry: AppText.retry
        }
    }
}

private struct ToastMessageView: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "checkmark.circle.fill")
            .font(AirTranslateDesign.Typography.label.weight(.semibold))
            .foregroundStyle(AirTranslateDesign.Palette.textPrimary)
            .padding(.horizontal, AirTranslateDesign.Spacing.sm)
            .padding(.vertical, AirTranslateDesign.Spacing.xs)
            .airConsoleSurface()
            .accessibilityAddTraits(.updatesFrequently)
    }
}

/// Expand the window to add the inspector while preserving the caption column's width.
/// Enforce the console width floor rather than wrapping its controls.
private struct MediaWorkspaceWindowSizer: NSViewRepresentable {
    let expanded: Bool
    let reduceMotion: Bool
    func makeNSView(context: Context) -> MediaSizingView { MediaSizingView() }
    func updateNSView(_ view: MediaSizingView, context: Context) {
        view.expanded = expanded
        view.reduceMotion = reduceMotion
        DispatchQueue.main.async { [weak view] in view?.applySize() }
    }
    final class MediaSizingView: NSView {
        var expanded = false
        var reduceMotion = false
        private var applied = false
        private var collapsedWidth: CGFloat?
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); applySize() }
        func applySize() {
            guard let window else { return }
            let previousFrame = window.frame
            window.contentMinSize = NSSize(
                width: MediaWorkspaceLayout.minimumWindowWidth(media: expanded),
                height: max(window.contentMinSize.height, AirTranslateDesign.mainWindowMinimumHeight)
            )
            guard applied != expanded else { return }
            guard !window.styleMask.contains(.fullScreen), let visible = window.screen?.visibleFrame else {
                applied = expanded
                return
            }
            var frame = previousFrame
            if expanded {
                collapsedWidth = frame.width
                frame.size.width = MediaWorkspaceLayout.expandedWindowWidth(from: frame.width, within: visible.width)
            } else if let collapsedWidth {
                frame.size.width = max(MediaWorkspaceLayout.captionMinimumWidth, min(collapsedWidth, visible.width))
            }
            frame.origin.x = max(visible.minX, min(frame.origin.x, visible.maxX - frame.width))
            applied = expanded
            window.setFrame(frame, display: true, animate: !reduceMotion)
        }
    }
}
