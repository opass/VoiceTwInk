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

        // Implementation: yPosition = screenFrame.minY + 24 (bottom pad) + 120 (recorder height) + 8 (gap)
        let expectedY = testScreenFrame.minY + 24 + 120 + 8
        #expect(frame.minY == expectedY, "HUD bottom must sit exactly the padding gap above MiniRecorder top edge")
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

        // Implementation: yPosition = screenFrame.maxY - 36 (notch height) - 8 (gap) - hudSize.height
        let expectedY = testScreenFrame.maxY - 36 - 8 - hudSize.height
        #expect(frame.minY == expectedY, "HUD top must sit exactly the padding gap below the notch's bottom edge")
        #expect(frame.midX == testScreenFrame.midX, "HUD must be horizontally centered under notch")
        #expect(frame.size == hudSize)
    }

    @Test("Fallback when given zero screen — returns frame with correct size, no crash")
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
