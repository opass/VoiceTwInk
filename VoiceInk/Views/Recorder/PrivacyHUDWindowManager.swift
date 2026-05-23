import SwiftUI
import AppKit
import Combine

/// Owns the PrivacyHUDPanel lifecycle. Observes AIEnhancementService's
/// currentPrivacyPayload and shows / hides / repositions accordingly.
@MainActor
class PrivacyHUDWindowManager: ObservableObject {
    private var panel: PrivacyHUDPanel?
    private var hostingController: NSHostingController<PrivacyHUDView>?
    private let enhancementService: AIEnhancementService
    private var cancellables: Set<AnyCancellable> = []

    init(enhancementService: AIEnhancementService) {
        self.enhancementService = enhancementService
        observePayload()
    }

    private func observePayload() {
        enhancementService.$currentPrivacyPayload
            .receive(on: DispatchQueue.main)
            .sink { [weak self] payload in
                guard let self else { return }
                if let payload {
                    self.showOrUpdate(with: payload)
                } else {
                    self.hide()
                }
            }
            .store(in: &cancellables)
    }

    private func showOrUpdate(with payload: PrivacyPayload) {
        if let panel, let hostingController {
            hostingController.rootView = PrivacyHUDView(payload: payload)
            // Re-measure and re-position after content update
            let size = measuredSize(host: hostingController)
            let frame = PrivacyHUDPositioner.calculateFrame(hudSize: size)
            panel.setFrame(frame, display: true)
            panel.orderFrontRegardless()
            return
        }

        let view = PrivacyHUDView(payload: payload)
        let host = NSHostingController(rootView: view)
        let initialSize = NSSize(width: 700, height: 100)
        let initialFrame = PrivacyHUDPositioner.calculateFrame(hudSize: initialSize)
        let newPanel = PrivacyHUDPanel(contentRect: initialFrame)
        newPanel.contentViewController = host

        // Force layout pass so we can measure intrinsic content size
        host.view.layoutSubtreeIfNeeded()
        let measuredSize = self.measuredSize(host: host)
        let measuredFrame = PrivacyHUDPositioner.calculateFrame(hudSize: measuredSize)
        newPanel.setFrame(measuredFrame, display: false)
        newPanel.orderFrontRegardless()

        self.panel = newPanel
        self.hostingController = host
    }

    /// Computes the panel size from the hosting controller's intrinsic content size,
    /// capped at 70% of the screen visible height so the HUD can never grow off-screen.
    private func measuredSize(host: NSHostingController<PrivacyHUDView>) -> NSSize {
        let fitting = host.view.fittingSize
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 800
        let maxHeight = screenHeight * 0.7
        let width: CGFloat = 700
        let height = min(max(fitting.height, 60), maxHeight)
        return NSSize(width: width, height: height)
    }

    private func hide() {
        panel?.orderOut(nil)
    }

    deinit {
        cancellables.removeAll()
    }
}
