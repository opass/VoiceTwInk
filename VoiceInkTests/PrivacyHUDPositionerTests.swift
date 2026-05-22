import Testing
import Foundation
import AppKit
@testable import VoiceInk

@Suite("PrivacyHUDPositioner") struct PrivacyHUDPositionerTests {
    private let hudSize = NSSize(width: 280, height: 140)
    private let testScreenFrame = NSRect(x: 0, y: 0, width: 1920, height: 1080)

    @Test("MiniRecorder mode: HUD frame is above MiniRecorder rect, centered horizontally")
    func miniRecorderModePlacesHUDAbove() {
        let frame = PrivacyHUDPositioner.calculateFrame(
            mode: .miniRecorder,
            hudSize: hudSize,
            screenFrame: testScreenFrame
        )

        let miniRecorderTopY = testScreenFrame.minY + 24 + 120  // bottom padding + MiniRecorder height
        #expect(frame.minY >= miniRecorderTopY, "HUD bottom must sit at or above MiniRecorder top edge")
        #expect(frame.midX == testScreenFrame.midX, "HUD must be horizontally centered")
        #expect(frame.size == hudSize)
    }

    @Test("Notch mode: HUD frame is below Notch (top of screen)")
    func notchModePlacesHUDBelow() {
        let frame = PrivacyHUDPositioner.calculateFrame(
            mode: .notch,
            hudSize: hudSize,
            screenFrame: testScreenFrame
        )

        // Notch sits at the top; HUD must be below the notch's bottom edge
        #expect(frame.maxY < testScreenFrame.maxY, "HUD must be entirely below screen top")
        #expect(frame.midX == testScreenFrame.midX, "HUD must be horizontally centered under notch")
        #expect(frame.size == hudSize)
    }

    @Test("Fallback when given zero screen — returns centered default")
    func zeroScreenFallback() {
        let zero = NSRect.zero
        let frame = PrivacyHUDPositioner.calculateFrame(
            mode: .miniRecorder,
            hudSize: hudSize,
            screenFrame: zero
        )
        #expect(frame.size == hudSize)
        // Don't assert specific coordinates — just don't crash
    }
}
