import Foundation

enum PredefinedPrompts {
    // Static UUIDs for predefined prompts.
    // Verbatim REUSES the original Default UUID so existing user state
    // (selectedPromptId pointing to "Default", triggerWords, isActive) carries
    // over with no data loss. Assistant keeps its original UUID but moves
    // from slot index 1 to slot index 9 (handled by the reorder step in
    // AIEnhancementService.initializePredefinedPrompts).
    static let verbatimPromptId   = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let assistantPromptId  = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    static let summaryPromptId    = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    static let dummySlot3Id       = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
    static let dummySlot4Id       = UUID(uuidString: "00000000-0000-0000-0000-000000000005")!
    static let dummySlot5Id       = UUID(uuidString: "00000000-0000-0000-0000-000000000006")!
    static let dummySlot6Id       = UUID(uuidString: "00000000-0000-0000-0000-000000000007")!
    static let dummySlot7Id       = UUID(uuidString: "00000000-0000-0000-0000-000000000008")!
    static let dummySlot8Id       = UUID(uuidString: "00000000-0000-0000-0000-000000000009")!
    static let dummySlot9Id       = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!

    // Backwards-compat alias — code paths referencing `defaultPromptId` still
    // resolve. Verbatim IS the new Default (reuses the same UUID).
    static let defaultPromptId = verbatimPromptId

    static var all: [CustomPrompt] {
        createDefaultPrompts()
    }

    static func createDefaultPrompts() -> [CustomPrompt] {
        let verbatimText = PromptTemplates.all.first { $0.title == "System Default" }?.promptText ?? ""
        let summaryText  = PromptTemplates.all.first { $0.title == "Summary" }?.promptText ?? ""

        func makeDummy(id: UUID, slotNumber: Int) -> CustomPrompt {
            CustomPrompt(
                id: id,
                title: "Slot \(slotNumber) (Unassigned)",
                promptText: verbatimText,
                icon: "questionmark.circle",
                description: "Unassigned hotkey slot. Currently behaves like Verbatim. Edit this prompt to assign a custom mode.",
                isPredefined: true,
                useSystemInstructions: true
            )
        }

        return [
            CustomPrompt(
                id: verbatimPromptId,
                title: "Verbatim",
                promptText: verbatimText,
                icon: "checkmark.seal.fill",
                description: "Preserve every sentence; only drop pure fillers and self-correction commands.",
                isPredefined: true,
                useSystemInstructions: true
            ),
            CustomPrompt(
                id: summaryPromptId,
                title: "Summary",
                promptText: summaryText,
                icon: "doc.text",
                description: "Light cleanup, ≥80% sentence retention. Local reorder allowed.",
                isPredefined: true,
                useSystemInstructions: true
            ),
            makeDummy(id: dummySlot3Id, slotNumber: 3),
            makeDummy(id: dummySlot4Id, slotNumber: 4),
            makeDummy(id: dummySlot5Id, slotNumber: 5),
            makeDummy(id: dummySlot6Id, slotNumber: 6),
            makeDummy(id: dummySlot7Id, slotNumber: 7),
            makeDummy(id: dummySlot8Id, slotNumber: 8),
            makeDummy(id: dummySlot9Id, slotNumber: 9),
            CustomPrompt(
                id: assistantPromptId,
                title: "Assistant",
                promptText: AIPrompts.assistantMode,
                icon: "bubble.left.and.bubble.right.fill",
                description: "AI assistant that provides direct answers to queries",
                isPredefined: true,
                useSystemInstructions: false
            )
        ]
    }
}
