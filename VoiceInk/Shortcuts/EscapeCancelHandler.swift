import AppKit
import CoreGraphics
import Carbon.HIToolbox

/// Captures ESC keypress during recording and triggers a full cancel:
/// recording stops, audio buffer discarded, no transcribe, no LLM call, no paste.
///
/// Implementation uses a CGEventTap (not NSEvent.addGlobalMonitorForEvents)
/// because the global monitor doesn't reliably fire when another CGEventTap
/// is active (VoiceInk's ShortcutMonitor uses one) AND a modifier key is held
/// — which is exactly what happens during push-to-talk recording. The tap
/// here listens specifically for ESC keyCode while ignoring modifier flag
/// state, so it fires whether the user pressed ESC alone or while still
/// holding the push-to-talk modifier.
///
/// The tap CONSUMES the ESC event (returns nil from callback) so the focused
/// app doesn't also see the ESC. This is intentional — the user pressed ESC
/// to cancel the recording, not to interact with the foreground app.
@MainActor
final class EscapeCancelHandler {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let onCancel: () async -> Void

    init(onCancel: @escaping () async -> Void) {
        self.onCancel = onCancel
    }

    /// Begin listening for ESC. Call when recording starts.
    func register() {
        guard eventTap == nil else { return }

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }
            let handler = Unmanaged<EscapeCancelHandler>.fromOpaque(userInfo).takeUnretainedValue()

            // Re-enable the tap if the system disabled it (timeout or by user input).
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = handler.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passUnretained(event)
            }

            guard type == .keyDown else {
                return Unmanaged.passUnretained(event)
            }

            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            guard keyCode == UInt16(kVK_Escape) else {
                return Unmanaged.passUnretained(event)
            }

            // Fire cancellation on main actor. Consume the ESC event so the
            // focused app doesn't also see it.
            Task { @MainActor in
                await handler.onCancel()
            }
            return nil
        }

        let mask = CGEventMask(1) << Int(CGEventType.keyDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return
        }

        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    /// Stop listening. Call when recording ends or cancels.
    func unregister() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
    }

    deinit {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }
    }
}
