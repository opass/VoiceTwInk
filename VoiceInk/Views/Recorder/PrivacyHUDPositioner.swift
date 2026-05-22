import AppKit
import Foundation

/// Computes the NSRect for the PrivacyHUDPanel based on which recorder mode is active.
/// HUD sits adjacent to the recorder so it visually belongs to the recording session
/// without modifying MiniRecorderView / NotchRecorderView themselves.
enum PrivacyHUDPositioner {
    /// Active recorder mode — read from the existing "RecorderType" UserDefaults key.
    /// Values written by RecorderUIManager: "mini" (default) or "notch".
    enum Mode {
        case miniRecorder
        case notch
    }

    /// Compute the frame for the HUD panel given the user's active recorder mode
    /// and the screen it should appear on.
    static func calculateFrame(
        mode: Mode,
        hudSize: NSSize,
        screenFrame: NSRect
    ) -> NSRect {
        guard screenFrame != .zero else {
            // Degenerate case (no screen / off-screen) — return a 0,0 origin frame so
            // the caller doesn't crash. The panel will be invisible until a real screen
            // is available.
            return NSRect(origin: .zero, size: hudSize)
        }

        let centerX = screenFrame.midX - (hudSize.width / 2)
        let padding: CGFloat = 8

        switch mode {
        case .miniRecorder:
            // MiniRecorder sits 24pt above the screen bottom (visibleFrame.minY + 24)
            // and is 120pt tall. HUD sits above it with `padding` gap.
            let miniRecorderBottomPadding: CGFloat = 24
            let miniRecorderHeight: CGFloat = 120
            let yPosition = screenFrame.minY + miniRecorderBottomPadding + miniRecorderHeight + padding
            return NSRect(x: centerX, y: yPosition, width: hudSize.width, height: hudSize.height)

        case .notch:
            // Notch hangs from the top of the screen; assume ~36pt notch depth (typical
            // MacBook Pro notch chin). HUD appears immediately below, centered.
            let notchHeight: CGFloat = 36
            let yPosition = screenFrame.maxY - notchHeight - padding - hudSize.height
            return NSRect(x: centerX, y: yPosition, width: hudSize.width, height: hudSize.height)
        }
    }

    /// Convenience for production callers — uses NSScreen.main's visibleFrame and reads
    /// recorder type from UserDefaults ("RecorderType" key; values "mini" or "notch").
    static func calculateFrame(hudSize: NSSize) -> NSRect {
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let recorderTypeRaw = UserDefaults.standard.string(forKey: "RecorderType") ?? "mini"
        let mode: Mode = (recorderTypeRaw == "notch") ? .notch : .miniRecorder
        return calculateFrame(mode: mode, hudSize: hudSize, screenFrame: screenFrame)
    }
}
