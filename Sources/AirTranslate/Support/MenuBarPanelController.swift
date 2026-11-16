import AppKit
import Observation
import SwiftUI

@MainActor
final class MenuBarPanelController: NSObject {
    private let popover = NSPopover()
    private let hostingController = NSHostingController(rootView: AnyView(EmptyView()))
    private var statusItem: NSStatusItem?
    private weak var session: TranslationSessionStore?
    private var isObservingSession = false

    override init() {
        super.init()
        popover.animates = true
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 360, height: 430)
        hostingController.sizingOptions = .preferredContentSize
        popover.contentViewController = hostingController
    }

    func install(session: TranslationSessionStore, openWindow: OpenWindowAction) {
        if self.session !== session {
            self.session = session
            // AppKit이 호스팅하는 상태바 패널에도 실제 Scene의 창 열기 동작을 전달한다.
            hostingController.rootView = AnyView(
                MenuBarStatusView(session: session, openWindow: openWindow)
            )
        }
        ensureStatusItem()
        updateStatusButton(using: session)
        observeSessionStateIfNeeded()
    }

    @objc
    private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else {
            return
        }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func ensureStatusItem() {
        guard statusItem == nil else {
            return
        }

        let item = NSStatusBar.system.statusItem(withLength: 28)
        item.isVisible = true
        statusItem = item

        guard let button = item.button else {
            return
        }

        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseDown])
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        let image = NSImage(systemSymbolName: "captions.bubble", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .medium))
        image?.isTemplate = true
        button.image = image
        button.toolTip = AppText.menuBarTitle
    }

    private func updateStatusButton(using session: TranslationSessionStore) {
        guard let button = statusItem?.button else {
            return
        }

        let title = menuBarTitle(for: session)
        if button.toolTip != title {
            button.toolTip = title
        }
        if button.accessibilityTitle() != title {
            button.setAccessibilityTitle(title)
        }
    }

    private func observeSessionStateIfNeeded() {
        guard !isObservingSession, session != nil else {
            return
        }

        isObservingSession = true
        trackSessionState()
    }

    private func trackSessionState() {
        guard let session else {
            isObservingSession = false
            return
        }

        withObservationTracking {
            _ = session.isRunning
            _ = session.isPaused
            _ = InterfaceLocalization.shared.preference
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                guard let session = self.session else {
                    self.isObservingSession = false
                    return
                }
                self.updateStatusButton(using: session)
                self.trackSessionState()
            }
        }
    }

    private func menuBarTitle(for session: TranslationSessionStore) -> String {
        if session.isPaused {
            return AppText.menuBarPausedTitle
        }
        if session.isRunning {
            return AppText.menuBarRunningTitle
        }
        return AppText.menuBarTitle
    }

}
