import AppKit

/// Captures global ESC keypress during recording. ESC triggers a full cancel:
/// recording stops, audio buffer discarded, no transcribe, no LLM call, no paste.
@MainActor
final class EscapeCancelHandler {
    private var monitor: Any?
    private let onCancel: () async -> Void

    init(onCancel: @escaping () async -> Void) {
        self.onCancel = onCancel
    }

    /// Begin listening for ESC. Call when recording starts.
    func register() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }   // 53 = ESC
            guard let self else { return }
            Task { @MainActor in
                await self.onCancel()
            }
        }
    }

    /// Stop listening. Call when recording ends or cancels.
    func unregister() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
