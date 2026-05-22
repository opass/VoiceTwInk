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
    private let hudSize = NSSize(width: 280, height: 140)

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
        let frame = PrivacyHUDPositioner.calculateFrame(hudSize: hudSize)

        if let panel, let hostingController {
            hostingController.rootView = PrivacyHUDView(payload: payload)
            panel.setFrame(frame, display: true)
            panel.orderFrontRegardless()
            return
        }

        let view = PrivacyHUDView(payload: payload)
        let host = NSHostingController(rootView: view)
        let newPanel = PrivacyHUDPanel(contentRect: frame)
        newPanel.contentView = host.view
        newPanel.orderFrontRegardless()
        self.panel = newPanel
        self.hostingController = host
    }

    private func hide() {
        panel?.orderOut(nil)
    }

    deinit {
        cancellables.removeAll()
    }
}
