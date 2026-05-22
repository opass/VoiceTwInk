# Privacy HUD Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a floating SwiftUI HUD that displays every context field about to be sent to the LLM during a recording, captured at record-start and locked until send, with ESC-to-cancel and visual differentiation between cloud and local destinations. Also bundles OPA-113 system context (time / timezone / locale).

**Architecture:** Independent `NSPanel` (`PrivacyHUDPanel`) hosting a SwiftUI view (`PrivacyHUDView`), binding to a single `currentPrivacyPayload` property on `AIEnhancementService` (existing `ObservableObject`). Capture coordination piggybacks on the existing record-start hook in `VoiceInkEngine.swift:219-222`. `getSystemMessage()` is modified to read from captured-at-record-start properties first, falling back to on-demand fetch if nil (so HUD failure never breaks enhance).

**Tech Stack:** Swift, SwiftUI, AppKit (NSPanel), Vision (existing OCR), Swift Testing (`@Test` + `#expect`, see existing `VoiceInkTests/VoiceInkTests.swift`).

**Spec reference:** `docs/superpowers/specs/2026-05-22-privacy-hud-design.md`

---

## File Structure

### Files to create

| Path | Responsibility |
|---|---|
| `VoiceInk/Models/PrivacyPayload.swift` | Data model: `PrivacyPayload` struct + `ContextField<T>` + `TranscriptState` + `ScreenContextValue` + `SystemContextValue` + `PrivacyDestination` enum and `isLocal` detection |
| `VoiceInk/Views/Recorder/PrivacyHUDView.swift` | SwiftUI view rendering `PrivacyPayload`. Per-field rows + destination footer. Cloud/local color theme |
| `VoiceInk/Views/Recorder/PrivacyHUDPanel.swift` | NSPanel hosting the SwiftUI view; transparent floating window matching `MiniRecorderPanel` style |
| `VoiceInk/Views/Recorder/PrivacyHUDPositioner.swift` | Compute NSRect adjacent to active recorder (above MiniRecorder, below Notch); reads `RecorderType` UserDefaults |
| `VoiceInk/Views/Recorder/PrivacyHUDWindowManager.swift` | Lifecycle controller — observes `enhancementService.currentPrivacyPayload`, shows/hides panel, repositions on recorder type change |
| `VoiceInk/Shortcuts/EscapeCancelHandler.swift` | Registers global ESC hotkey during recording; calls `engine.cancelRecording()` |
| `VoiceInkTests/PrivacyPayloadTests.swift` | Swift Testing tests for `PrivacyDestination.isLocal`, `ContextField` semantics, `PrivacyPayload` assembly |
| `VoiceInkTests/PrivacyHUDPositionerTests.swift` | Tests for positioner with mock screen rects |

### Files to modify

| Path | What changes |
|---|---|
| `VoiceInk/Services/AIEnhancement/AIEnhancementService.swift` | Add 4 new `@Published` properties (`useSelectedTextContext`, `useCustomVocabularyContext`, `lastCapturedSelectedText`, `lastCapturedVocabulary`, `lastCapturedSystemContext`, `currentPrivacyPayload`); 5 new methods (`captureSelectedTextContext`, `captureVocabularyContext`, `captureSystemContext`, `assemblePrivacyPayload`, `clearPrivacyPayload`); modify `getSystemMessage()` (lines 145-202) for property-first + fallback + new toggles + SYSTEM_CONTEXT block |
| `VoiceInk/Transcription/Engine/VoiceInkEngine.swift` | Extend capture block (line ~219-222) with 3 new capture methods + `assemblePrivacyPayload`; add `clearPrivacyPayload` to recording end (around line 96-120) and cancel paths (`cancelRecording` line 304) |
| `VoiceInk/Views/Components/EnhancementSettingsPanel.swift` | Add 2 new Toggle entries (line ~46-60 area) for `useSelectedTextContext` + `useCustomVocabularyContext` |
| `VoiceInk/Views/MenuBarView.swift` | Add 2 menubar toggles matching settings (line ~166-185 area) |
| `VoiceInk/VoiceInk.swift` | Instantiate `PrivacyHUDWindowManager` at app init, alongside existing recorder window managers |
| `CLAUDE.md` | Update "known privacy gap" section (lines ~64-71) — mark resolved; add Append-only log entry recording the fork divergences |

---

## Conventions

- Run unit tests via: `xcodebuild test -project VoiceInk.xcodeproj -scheme VoiceInk -destination 'platform=macOS' -only-testing:VoiceInkTests/<TestSuiteName>/<testName>`
- Full app build / dog-food: `make local && make relaunch` (per project Makefile; recompiles + restarts via Personal Team signing)
- Commit format: conventional commits (`feat:`, `fix:`, `test:`, `docs:`), bodies explain why
- Tests use Swift Testing (`@Test`, `#expect`), not XCTest

---

## Task 1: Data model — PrivacyPayload + PrivacyDestination

**Files:**
- Create: `VoiceInk/Models/PrivacyPayload.swift`
- Test: `VoiceInkTests/PrivacyPayloadTests.swift`

- [ ] **Step 1: Write the failing test (PrivacyDestination cloud/local detection)**

Create `VoiceInkTests/PrivacyPayloadTests.swift`:

```swift
import Testing
import Foundation
@testable import VoiceInk

@Suite("PrivacyDestination") struct PrivacyDestinationTests {
    @Test("Anthropic URL is classified cloud")
    func anthropicIsCloud() {
        let dest = PrivacyDestination.detect(
            providerLabel: "Claude",
            baseURL: URL(string: "https://api.anthropic.com")!
        )
        #expect(dest == .cloud(providerLabel: "Claude"))
    }

    @Test("OpenAI URL is classified cloud")
    func openaiIsCloud() {
        let dest = PrivacyDestination.detect(
            providerLabel: "OpenAI",
            baseURL: URL(string: "https://api.openai.com")!
        )
        #expect(dest == .cloud(providerLabel: "OpenAI"))
    }

    @Test("Ollama localhost is classified local")
    func ollamaIsLocal() {
        let dest = PrivacyDestination.detect(
            providerLabel: "Ollama",
            baseURL: URL(string: "http://localhost:11434")!
        )
        #expect(dest == .local(providerLabel: "Ollama"))
    }

    @Test("127.0.0.1 is classified local")
    func ipv4LocalhostIsLocal() {
        let dest = PrivacyDestination.detect(
            providerLabel: "Custom",
            baseURL: URL(string: "http://127.0.0.1:8080")!
        )
        #expect(dest == .local(providerLabel: "Custom"))
    }

    @Test("Custom remote URL with localhost suffix is still cloud")
    func cloudHostWithLocalhostInName() {
        let dest = PrivacyDestination.detect(
            providerLabel: "Custom",
            baseURL: URL(string: "https://localhost-proxy.example.com")!
        )
        #expect(dest == .cloud(providerLabel: "Custom"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild test -project VoiceInk.xcodeproj -scheme VoiceInk \
  -destination 'platform=macOS' \
  -only-testing:VoiceInkTests/PrivacyDestinationTests 2>&1 | tail -20
```

Expected: FAIL — `Cannot find 'PrivacyDestination' in scope`.

- [ ] **Step 3: Write the data model**

Create `VoiceInk/Models/PrivacyPayload.swift`:

```swift
import Foundation

/// The single snapshot of everything about to be sent to the LLM at this moment.
struct PrivacyPayload: Equatable {
    let timestamp: Date
    let transcript: TranscriptState
    let selectedText: ContextField<String>
    let clipboard: ContextField<String>
    let screenContext: ContextField<ScreenContextValue>
    let customVocabulary: ContextField<String>
    let systemContext: ContextField<SystemContextValue>
    let destination: PrivacyDestination
}

enum TranscriptState: Equatable {
    case recording
    case finished(String)
}

/// Five-state semantics for any single field that may or may not be in the outgoing payload.
enum ContextField<T: Equatable>: Equatable {
    /// Global toggle is off, or permission is denied.
    case disabled
    /// Toggle on but content is empty (no selection, empty clipboard, empty vocab).
    case empty
    /// Async capture in progress (only screen OCR uses this in practice).
    case pending
    /// Was pending; release happened before capture finished.
    case omitted
    /// Has a value that will be sent.
    case present(T)
}

struct ScreenContextValue: Equatable {
    let windowTitle: String
    let appName: String
    let extractedText: String
}

struct SystemContextValue: Equatable {
    let timestamp: Date
    let timezone: String
    let dayOfWeek: String
    let locale: String
}

enum PrivacyDestination: Equatable {
    case local(providerLabel: String)
    case cloud(providerLabel: String)

    /// Classify a destination by its base URL host. localhost / 127.0.0.1 / ::1 → local.
    static func detect(providerLabel: String, baseURL: URL) -> PrivacyDestination {
        let host = baseURL.host?.lowercased() ?? ""
        let localHosts: Set<String> = ["localhost", "127.0.0.1", "::1", "0.0.0.0"]
        if localHosts.contains(host) {
            return .local(providerLabel: providerLabel)
        }
        return .cloud(providerLabel: providerLabel)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
xcodebuild test -project VoiceInk.xcodeproj -scheme VoiceInk \
  -destination 'platform=macOS' \
  -only-testing:VoiceInkTests/PrivacyDestinationTests 2>&1 | tail -20
```

Expected: PASS — all 5 tests succeed.

- [ ] **Step 5: Commit**

```bash
git add VoiceInk/Models/PrivacyPayload.swift VoiceInkTests/PrivacyPayloadTests.swift
git commit -m "feat(privacy-hud): add PrivacyPayload model + PrivacyDestination detection

Foundational data types for the Privacy HUD. ContextField<T> uses
five explicit cases (disabled/empty/pending/omitted/present) instead
of nil + booleans so render decisions stay unambiguous.

PrivacyDestination.detect() classifies any provider as local when
its baseURL host is localhost / 127.0.0.1 / ::1 / 0.0.0.0, else
cloud — feeding Q7's visual differentiation.

Part of OPA-111 / OPA-112."
```

---

## Task 2: Global toggle — `useSelectedTextContext`

**Files:**
- Modify: `VoiceInk/Services/AIEnhancement/AIEnhancementService.swift` (lines 27-38 area for toggle property; line 86-88 for init)
- Modify: `VoiceInk/Views/Components/EnhancementSettingsPanel.swift` (lines 45-63 area)
- Modify: `VoiceInk/Views/MenuBarView.swift` (lines 166-187 area)

- [ ] **Step 1: Add @Published property + init in AIEnhancementService**

Find the existing `useClipboardContext` declaration (~line 27) and add `useSelectedTextContext` next to it:

```swift
@Published var useSelectedTextContext: Bool {
    didSet {
        UserDefaults.standard.set(useSelectedTextContext, forKey: "useSelectedTextContext")
        NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
    }
}
```

In `init()` (around line 86-88), add init line right after the existing `useScreenCaptureContext` init:

```swift
// Default ON to match upstream behaviour (selected text was always sent if AX granted)
self.useSelectedTextContext = UserDefaults.standard.object(forKey: "useSelectedTextContext") as? Bool ?? true
```

Note: `UserDefaults.standard.object(forKey:) as? Bool` is used (not `.bool(forKey:)`) so we can distinguish "user explicitly set false" from "never set". Default = true preserves upstream behaviour for upgrading users.

- [ ] **Step 2: Add Toggle in EnhancementSettingsPanel.swift**

In `VoiceInk/Views/Components/EnhancementSettingsPanel.swift`, find the existing `Toggle(isOn: $enhancementService.useScreenCaptureContext)` block (around line 54) and add immediately after its `.toggleStyle(.switch)`:

```swift
Toggle(isOn: $enhancementService.useSelectedTextContext) {
    HStack(spacing: 4) {
        Text("Selected Text")
        InfoTip("Include the text currently selected in any app when enhancing. Requires Accessibility permission.")
    }
}
.toggleStyle(.switch)
```

- [ ] **Step 3: Add menubar toggle in MenuBarView.swift**

In `VoiceInk/Views/MenuBarView.swift`, find the existing `useScreenCaptureContext` block (line ~179) and add a similar block right after for `useSelectedTextContext`. Copy the exact same pattern:

```swift
Button {
    enhancementService.useSelectedTextContext.toggle()
} label: {
    HStack {
        Text("Selected Text Context")
        Spacer()
        if enhancementService.useSelectedTextContext {
            Image(systemName: "checkmark")
        }
    }
}
```

(Match the precise pattern used by the existing two toggles in that file — find the section that begins at line 166 and follow its style.)

- [ ] **Step 4: Build to verify**

```bash
make local 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add VoiceInk/Services/AIEnhancement/AIEnhancementService.swift \
       VoiceInk/Views/Components/EnhancementSettingsPanel.swift \
       VoiceInk/Views/MenuBarView.swift
git commit -m "feat(privacy): add useSelectedTextContext global toggle

Selected text was previously sent silently whenever Accessibility
permission was granted (no UI toggle, no preview). Adding an explicit
global toggle closes one half of the known privacy gap; default is
ON to match upstream behaviour for existing users.

Part of OPA-111 (Q4 — global toggles only, no per-prompt config)."
```

---

## Task 3: Global toggle — `useCustomVocabularyContext`

**Files:** same three as Task 2

- [ ] **Step 1: Add @Published property in AIEnhancementService**

Right after the `useSelectedTextContext` property added in Task 2:

```swift
@Published var useCustomVocabularyContext: Bool {
    didSet {
        UserDefaults.standard.set(useCustomVocabularyContext, forKey: "useCustomVocabularyContext")
        NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
    }
}
```

In `init()`, after the `useSelectedTextContext` init line:

```swift
self.useCustomVocabularyContext = UserDefaults.standard.object(forKey: "useCustomVocabularyContext") as? Bool ?? true
```

- [ ] **Step 2: Add Toggle to settings panel**

Right after the `useSelectedTextContext` Toggle block in `EnhancementSettingsPanel.swift`:

```swift
Toggle(isOn: $enhancementService.useCustomVocabularyContext) {
    HStack(spacing: 4) {
        Text("Custom Vocabulary")
        InfoTip("Include your custom vocabulary list to help with proper nouns and technical terms.")
    }
}
.toggleStyle(.switch)
```

- [ ] **Step 3: Add menubar toggle**

Right after the `useSelectedTextContext` menubar Button block in `MenuBarView.swift`, add the matching pattern for `useCustomVocabularyContext`.

- [ ] **Step 4: Build**

```bash
make local 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add VoiceInk/Services/AIEnhancement/AIEnhancementService.swift \
       VoiceInk/Views/Components/EnhancementSettingsPanel.swift \
       VoiceInk/Views/MenuBarView.swift
git commit -m "feat(privacy): add useCustomVocabularyContext global toggle

Custom vocabulary was previously sent silently whenever the user had
non-empty vocab entries. Adding the global toggle closes the other
half of the silent-fields gap. Default ON to preserve upstream
behaviour for existing users.

Part of OPA-111 (Q4 — global toggles only)."
```

---

## Task 4: Capture selected text at record-start

**Files:**
- Modify: `VoiceInk/Services/AIEnhancement/AIEnhancementService.swift`

- [ ] **Step 1: Add `lastCapturedSelectedText` property**

In `AIEnhancementService` (next to existing `lastCapturedClipboard` at line 78):

```swift
@Published var lastCapturedSelectedText: String?
```

- [ ] **Step 2: Add capture method**

Near the other capture methods (after `captureScreenContext()` at line ~398-408):

```swift
func captureSelectedTextContext() async {
    guard AXIsProcessTrusted() else {
        lastCapturedSelectedText = nil
        return
    }
    lastCapturedSelectedText = await SelectedTextService.fetchSelectedText()
}
```

- [ ] **Step 3: Add to `clearCapturedContexts()` (line ~414-417)**

Modify the existing method:

```swift
func clearCapturedContexts() {
    lastCapturedClipboard = nil
    lastCapturedSelectedText = nil
    screenCaptureService.lastCapturedText = nil
}
```

- [ ] **Step 4: Build**

```bash
make local 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add VoiceInk/Services/AIEnhancement/AIEnhancementService.swift
git commit -m "feat(privacy): capture selected text at record-start

Move SelectedTextService.fetchSelectedText() from send-time
(getSystemMessage) to record-start (called explicitly by
VoiceInkEngine). The value is held in lastCapturedSelectedText
so the Privacy HUD can display exactly what will be sent and so
the eventual LLM payload matches the HUD (WYSIWYG).

This changes upstream semantics: previously the selection at
the moment of LLM-send was sent; now the selection at the
moment of record-start is sent. Aligns with OPA-112 Q3
capture-at-record-start design.

Part of OPA-111."
```

---

## Task 5: Capture custom vocabulary at record-start

**Files:**
- Modify: `VoiceInk/Services/AIEnhancement/AIEnhancementService.swift`

- [ ] **Step 1: Add property**

```swift
@Published var lastCapturedVocabulary: String?
```

- [ ] **Step 2: Add capture method**

```swift
func captureVocabularyContext() {
    let vocab = customVocabularyService.getCustomVocabulary(from: modelContext)
    lastCapturedVocabulary = vocab.isEmpty ? nil : vocab
}
```

(Note: `customVocabularyService.getCustomVocabulary(from:)` returns a `String` — see `CustomVocabularyService.swift:10`.)

- [ ] **Step 3: Extend `clearCapturedContexts()`**

```swift
func clearCapturedContexts() {
    lastCapturedClipboard = nil
    lastCapturedSelectedText = nil
    lastCapturedVocabulary = nil
    screenCaptureService.lastCapturedText = nil
}
```

- [ ] **Step 4: Build**

```bash
make local 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add VoiceInk/Services/AIEnhancement/AIEnhancementService.swift
git commit -m "feat(privacy): capture custom vocabulary at record-start

Move vocab fetch from getSystemMessage() (send-time) to a
captureVocabularyContext() method called at record-start. Held
in lastCapturedVocabulary for HUD display + send.

Part of OPA-111."
```

---

## Task 6: Capture system context at record-start (OPA-113 bundled)

**Files:**
- Modify: `VoiceInk/Services/AIEnhancement/AIEnhancementService.swift`

- [ ] **Step 1: Add property**

```swift
@Published var lastCapturedSystemContext: SystemContextValue?
```

- [ ] **Step 2: Add capture method**

```swift
func captureSystemContext() {
    let now = Date()
    let calendar = Calendar.current
    let weekdayIndex = calendar.component(.weekday, from: now) - 1   // 1-based → 0-based
    let weekday = calendar.weekdaySymbols[weekdayIndex]
    lastCapturedSystemContext = SystemContextValue(
        timestamp: now,
        timezone: TimeZone.current.identifier,
        dayOfWeek: weekday,
        locale: Locale.current.identifier
    )
}
```

- [ ] **Step 3: Extend `clearCapturedContexts()`**

```swift
func clearCapturedContexts() {
    lastCapturedClipboard = nil
    lastCapturedSelectedText = nil
    lastCapturedVocabulary = nil
    lastCapturedSystemContext = nil
    screenCaptureService.lastCapturedText = nil
}
```

- [ ] **Step 4: Build**

```bash
make local 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add VoiceInk/Services/AIEnhancement/AIEnhancementService.swift
git commit -m "feat(privacy): capture system context at record-start (OPA-113)

Time / timezone / day-of-week / locale are captured at
record-start and stored in lastCapturedSystemContext. This
will appear in the LLM system message as <SYSTEM_CONTEXT>
once getSystemMessage() is updated in a later task, so
Assistant Mode can answer 'what time is it' etc.

Bundles OPA-113 into the Privacy HUD work because both
touch the same getSystemMessage() function — avoiding a
second round of merge cost.

Part of OPA-111 / OPA-113."
```

---

## Task 7: Assemble + clear PrivacyPayload state

**Files:**
- Modify: `VoiceInk/Services/AIEnhancement/AIEnhancementService.swift`

- [ ] **Step 1: Add `currentPrivacyPayload` property**

```swift
@Published var currentPrivacyPayload: PrivacyPayload?
```

- [ ] **Step 2: Add `assemblePrivacyPayload()`**

Add after the capture methods. This composes the snapshot from all the `lastCaptured*` fields plus toggle state:

```swift
/// Compose a PrivacyPayload from current captured state + toggle state + destination.
/// Called at record-start after all capture methods have fired and again whenever
/// async OCR completes (so the screenContext field transitions pending → present).
func assemblePrivacyPayload() {
    let selectedField: ContextField<String> = {
        guard useSelectedTextContext else { return .disabled }
        guard AXIsProcessTrusted() else { return .disabled }
        guard let text = lastCapturedSelectedText, !text.isEmpty else { return .empty }
        return .present(text)
    }()

    let clipboardField: ContextField<String> = {
        guard useClipboardContext else { return .disabled }
        guard let text = lastCapturedClipboard, !text.isEmpty else { return .empty }
        return .present(text)
    }()

    let screenField: ContextField<ScreenContextValue> = {
        guard useScreenCaptureContext else { return .disabled }
        guard CGPreflightScreenCaptureAccess() else { return .disabled }
        // ScreenCaptureService.lastCapturedText is a single string. We have window
        // title / appName earlier in the capture but the existing service merges
        // them into a single string. Parse what we can; if no text yet, .pending.
        guard let raw = screenCaptureService.lastCapturedText, !raw.isEmpty else { return .pending }
        return .present(ScreenContextValue(windowTitle: "", appName: "", extractedText: raw))
    }()

    let vocabField: ContextField<String> = {
        guard useCustomVocabularyContext else { return .disabled }
        guard let v = lastCapturedVocabulary, !v.isEmpty else { return .empty }
        return .present(v)
    }()

    let systemField: ContextField<SystemContextValue> = {
        guard let sys = lastCapturedSystemContext else { return .empty }
        return .present(sys)
    }()

    let providerLabel = aiService.selectedProvider.displayName
    let baseURL = aiService.currentBaseURL ?? URL(string: "https://api.anthropic.com")!
    let destination = PrivacyDestination.detect(providerLabel: providerLabel, baseURL: baseURL)

    currentPrivacyPayload = PrivacyPayload(
        timestamp: Date(),
        transcript: .recording,
        selectedText: selectedField,
        clipboard: clipboardField,
        screenContext: screenField,
        customVocabulary: vocabField,
        systemContext: systemField,
        destination: destination
    )
}
```

Notes:
- The `screenContext` parser is intentionally simple — it preserves the existing string format. Improving `ScreenCaptureService` to return structured `(windowTitle, appName, extractedText)` is out of scope.
- `aiService.selectedProvider.displayName` and `aiService.currentBaseURL` are read from existing AIService API. Verify the exact property names exist when reading `AIService.swift`; if `displayName` doesn't exist, use `String(describing:)` on the enum case, and if `currentBaseURL` isn't surfaced add a simple computed property that returns the URL for the current provider's endpoint (the LLMKitClient calls already construct these — pick the same URL).

- [ ] **Step 3: Add `clearPrivacyPayload()`**

```swift
func clearPrivacyPayload() {
    currentPrivacyPayload = nil
    clearCapturedContexts()
}
```

- [ ] **Step 4: Quick build check**

```bash
make local 2>&1 | tail -5
```

If build fails on `aiService.selectedProvider.displayName` or `aiService.currentBaseURL`, fix per the note in Step 2 — either add a `displayName` extension to the provider enum, or surface the baseURL via a new computed property in `AIService`.

Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add VoiceInk/Services/AIEnhancement/AIEnhancementService.swift
git commit -m "feat(privacy): assemble currentPrivacyPayload from captured state

Single source of truth for what's about to be sent. Composes
PrivacyPayload from the lastCaptured* properties + toggle state +
permission state + destination classification.

This is the single property the HUD will observe (next task).

Part of OPA-111."
```

---

## Task 8: Update `getSystemMessage` for property-first read + new toggles + SYSTEM_CONTEXT

**Files:**
- Modify: `VoiceInk/Services/AIEnhancement/AIEnhancementService.swift` (lines 145-202)

- [ ] **Step 1: Rewrite `getSystemMessage()` body**

Replace the entire existing function (lines 145-202) with:

```swift
private func getSystemMessage(for mode: EnhancementPrompt) async -> String {
    // Selected text — read property first; fall back to on-demand fetch if HUD
    // coordinator never ran (defensive — keeps upstream behaviour as a safety net).
    let selectedTextContext: String = await {
        guard useSelectedTextContext else { return "" }
        guard AXIsProcessTrusted() else { return "" }
        let captured: String?
        if let cached = lastCapturedSelectedText {
            captured = cached
        } else {
            captured = await SelectedTextService.fetchSelectedText()
        }
        guard let text = captured, !text.isEmpty else { return "" }
        return "\n\n<CURRENTLY_SELECTED_TEXT>\n\(text)\n</CURRENTLY_SELECTED_TEXT>"
    }()

    let clipboardContext = if useClipboardContext,
                              let clipboardText = lastCapturedClipboard,
                              !clipboardText.isEmpty {
        "\n\n<CLIPBOARD_CONTEXT>\n\(clipboardText)\n</CLIPBOARD_CONTEXT>"
    } else {
        ""
    }

    let screenCaptureContext = if useScreenCaptureContext,
                                   let capturedText = screenCaptureService.lastCapturedText,
                                   !capturedText.isEmpty {
        "\n\n<CURRENT_WINDOW_CONTEXT>\n\(capturedText)\n</CURRENT_WINDOW_CONTEXT>"
    } else {
        ""
    }

    // Custom vocabulary — property first, fall back to on-demand
    let customVocabulary: String = {
        guard useCustomVocabularyContext else { return "" }
        if let cached = lastCapturedVocabulary { return cached }
        return customVocabularyService.getCustomVocabulary(from: modelContext)
    }()

    // System context (OPA-113)
    let systemContextSection: String = {
        guard let sys = lastCapturedSystemContext else { return "" }
        let iso = ISO8601DateFormatter().string(from: sys.timestamp)
        return """


        <SYSTEM_CONTEXT>
        Current time: \(iso)
        Timezone: \(sys.timezone)
        Day of week: \(sys.dayOfWeek)
        Locale: \(sys.locale)
        </SYSTEM_CONTEXT>
        """
    }()

    let allContextSections = systemContextSection + selectedTextContext + clipboardContext + screenCaptureContext

    let customVocabularySection = if !customVocabulary.isEmpty {
        """


        The following are important vocabulary words, proper nouns, and technical terms. When these words or similar-sounding words appear in the <TRANSCRIPT>, ensure they are spelled EXACTLY as shown below:
        <CUSTOM_VOCABULARY>
        \(customVocabulary)
        </CUSTOM_VOCABULARY>
        """
    } else {
        ""
    }

    let finalContextSection = allContextSections + customVocabularySection

    if let activePrompt = activePrompt {
        if activePrompt.id == PredefinedPrompts.assistantPromptId {
            return activePrompt.promptText + finalContextSection
        } else {
            return activePrompt.finalPromptText + finalContextSection
        }
    } else {
        let defaultPrompt = allPrompts.first(where: { $0.id == PredefinedPrompts.defaultPromptId }) ?? allPrompts.first!
        return defaultPrompt.finalPromptText + finalContextSection
    }
}
```

Key changes from original:
1. Selected text gated by `useSelectedTextContext` (new toggle) AND property-first read
2. Custom vocabulary gated by `useCustomVocabularyContext` (new toggle) AND property-first read
3. New `<SYSTEM_CONTEXT>` section at the top of `allContextSections`
4. Clipboard / Screen context unchanged (already property-based + toggle-gated)

- [ ] **Step 2: Build**

```bash
make local 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Smoke-test by inspecting `lastSystemMessageSent`**

Quick mental check: the existing `lastSystemMessageSent` property captures whatever was sent (line 217). To verify, dog-food in the next task once VoiceInkEngine is wired up.

- [ ] **Step 4: Commit**

```bash
git add VoiceInk/Services/AIEnhancement/AIEnhancementService.swift
git commit -m "feat(privacy): rewrite getSystemMessage with property-first read + SYSTEM_CONTEXT

Three changes:
1. Selected text + custom vocabulary now gated by the new global
   toggles added in earlier tasks. Both also read from the
   lastCaptured* properties first, falling back to on-demand fetch
   if the property is nil (compat safety net for the case where
   HUD coordinator never ran — e.g. recording started outside the
   normal hotkey path).
2. New <SYSTEM_CONTEXT> section at the head of the assembled
   context — time, timezone, day-of-week, locale (OPA-113).
3. Clipboard and screen context paths unchanged (already property-
   based and toggle-gated upstream).

The fallback is intentionally defensive — owner noted it's slightly
over-engineered but worth keeping as a safety net for fork merge
edge cases.

Part of OPA-111 / OPA-113."
```

---

## Task 9: Wire VoiceInkEngine capture block + clear on end/cancel

**Files:**
- Modify: `VoiceInk/Transcription/Engine/VoiceInkEngine.swift` (lines 219-222 area + line ~96-120 + line 304)

- [ ] **Step 1: Extend capture block (line 219-222)**

Replace:

```swift
if let enhancementService = self.enhancementService {
    enhancementService.captureClipboardContext()
    await enhancementService.captureScreenContext()
}
```

With:

```swift
if let enhancementService = self.enhancementService {
    enhancementService.captureClipboardContext()
    await enhancementService.captureSelectedTextContext()
    enhancementService.captureVocabularyContext()
    enhancementService.captureSystemContext()
    await enhancementService.captureScreenContext()
    enhancementService.assemblePrivacyPayload()
}
```

Order matters: instant captures first (clipboard / selected / vocab / system), then async OCR last, then assemble.

Note `captureScreenContext()` was already `await`-ed; the chain now waits for OCR before assembling the initial payload, which means the very first `currentPrivacyPayload` already has screen context if OCR finished. For super-short recordings where OCR takes longer than the recording, the engine still releases — and `getSystemMessage` falls through to `screenCaptureService.lastCapturedText` being nil → screen context omitted (matches upstream).

- [ ] **Step 2: Clear on recording end (around line 96-120)**

Find the `toggleRecord` function's record-end branch (around line 93-120 where `recordingState = .transcribing` is set, after `await recorder.stopRecording()`). Add at the end of that branch (after the transcribe + enhance pipeline finishes — track down the actual completion point; if it's in a continuation after `recorder.stopRecording()`, add there):

Concrete location: after the `enhance()` call completes and result is processed. In current code this likely happens inside the closure that runs after stop. Search for where `recordingState = .idle` is set after a successful recording end — `clearPrivacyPayload()` should be called there.

```swift
self.enhancementService?.clearPrivacyPayload()
```

- [ ] **Step 3: Clear on cancel (line 304's `cancelRecording`)**

In `cancelRecording()` (lines 304-328), add at the end (after the switch statement, before/after `finishRecorderSession()`):

```swift
self.enhancementService?.clearPrivacyPayload()
```

- [ ] **Step 4: Build**

```bash
make local 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Manual smoke test**

```bash
make relaunch
```

Then trigger a recording (push-to-talk), say something, release. The recording + enhancement should still work end-to-end (no UI HUD yet, but the underlying capture pipeline is intact).

- [ ] **Step 6: Commit**

```bash
git add VoiceInk/Transcription/Engine/VoiceInkEngine.swift
git commit -m "feat(privacy): wire record-start capture coordination

Extend the existing capture block in toggleRecord() with the new
selected-text / vocab / system-context captures and the
assemblePrivacyPayload call. Order: instant captures first, async
OCR last, then assemble — so currentPrivacyPayload is populated as
soon as possible after record-start.

clearPrivacyPayload() is now called on both recording end (normal
completion) and cancellation paths, so the payload doesn't leak
between sessions.

Part of OPA-111."
```

---

## Task 10: PrivacyHUDPositioner — adjacent-to-recorder placement

**Files:**
- Create: `VoiceInk/Views/Recorder/PrivacyHUDPositioner.swift`
- Test: `VoiceInkTests/PrivacyHUDPositionerTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `VoiceInkTests/PrivacyHUDPositionerTests.swift`:

```swift
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

        let miniRecorderTopY = testScreenFrame.minY + 24 + 120  // padding + MiniRecorder height (per MiniRecorderPanel)
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
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -project VoiceInk.xcodeproj -scheme VoiceInk \
  -destination 'platform=macOS' \
  -only-testing:VoiceInkTests/PrivacyHUDPositionerTests 2>&1 | tail -20
```

Expected: FAIL — `Cannot find 'PrivacyHUDPositioner'`.

- [ ] **Step 3: Create the positioner**

Create `VoiceInk/Views/Recorder/PrivacyHUDPositioner.swift`:

```swift
import AppKit
import Foundation

/// Computes the NSRect for the PrivacyHUDPanel based on which recorder mode is active.
/// HUD sits adjacent to the recorder so it visually belongs to the recording session
/// without modifying MiniRecorderView / NotchRecorderView themselves.
enum PrivacyHUDPositioner {
    /// Active recorder mode — read from the existing `RecorderType` UserDefaults key.
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
            // MiniRecorder sits 24pt above the screen bottom and is 120pt tall.
            // HUD sits above it, with `padding` gap.
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

    /// Convenience for production callers — uses NSScreen.main and reads recorder type
    /// from UserDefaults ("RecorderType" key; values "miniRecorder" or "notch").
    static func calculateFrame(hudSize: NSSize) -> NSRect {
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let recorderTypeRaw = UserDefaults.standard.string(forKey: "RecorderType") ?? "miniRecorder"
        let mode: Mode = (recorderTypeRaw == "notch") ? .notch : .miniRecorder
        return calculateFrame(mode: mode, hudSize: hudSize, screenFrame: screenFrame)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -project VoiceInk.xcodeproj -scheme VoiceInk \
  -destination 'platform=macOS' \
  -only-testing:VoiceInkTests/PrivacyHUDPositionerTests 2>&1 | tail -20
```

Expected: PASS — all 3 tests succeed.

- [ ] **Step 5: Commit**

```bash
git add VoiceInk/Views/Recorder/PrivacyHUDPositioner.swift \
       VoiceInkTests/PrivacyHUDPositionerTests.swift
git commit -m "feat(privacy-hud): add PrivacyHUDPositioner

Calculates the HUD panel frame relative to the active recorder
mode — above MiniRecorder (which sits at bottom-center, 120pt
tall, 24pt from edge) or below the Notch (~36pt deep).

Uses the existing 'RecorderType' UserDefaults key to detect mode
so no changes are needed to the recorder window managers.

Part of OPA-111."
```

---

## Task 11: PrivacyHUDView SwiftUI

**Files:**
- Create: `VoiceInk/Views/Recorder/PrivacyHUDView.swift`

- [ ] **Step 1: Create the view**

Create `VoiceInk/Views/Recorder/PrivacyHUDView.swift`:

```swift
import SwiftUI

/// Visual rendering of the PrivacyPayload. Pure presentation — no business logic.
/// Each ContextField is rendered as a single row; .disabled and .empty cases are
/// not rendered at all so the HUD shrinks naturally when fields are absent.
struct PrivacyHUDView: View {
    let payload: PrivacyPayload

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            renderField(name: "Selected", icon: "✂️", field: payload.selectedText) { text in
                truncate(text, max: 50)
            }
            renderField(name: "Clipboard", icon: "📋", field: payload.clipboard) { text in
                truncate(text, max: 50)
            }
            renderField(name: "Screen", icon: "🖥", field: payload.screenContext) { val in
                truncate(val.extractedText, max: 50)
            }
            renderField(name: "Vocab", icon: "📚", field: payload.customVocabulary) { text in
                truncate(text, max: 50)
            }
            renderField(name: "Time", icon: "🕐", field: payload.systemContext) { val in
                "\(val.dayOfWeek) \(formatTime(val.timestamp)) (\(val.timezone))"
            }

            Divider().opacity(0.4)
            destinationFooter
        }
        .padding(10)
        .background(backgroundColor)
        .cornerRadius(10)
        .shadow(radius: 4)
        .frame(maxWidth: 280)
    }

    // MARK: - Field row

    @ViewBuilder
    private func renderField<T>(
        name: String,
        icon: String,
        field: ContextField<T>,
        valueFormatter: (T) -> String
    ) -> some View {
        switch field {
        case .disabled, .empty:
            EmptyView()                                 // hide row entirely
        case .pending:
            HStack(spacing: 6) {
                Text(icon).font(.system(size: 12))
                Text(name).font(.system(size: 11, weight: .semibold))
                Text("identifying...").font(.system(size: 11)).opacity(0.6)
                ProgressView().scaleEffect(0.5).frame(width: 12, height: 12)
            }
        case .omitted:
            HStack(spacing: 6) {
                Text(icon).font(.system(size: 12)).opacity(0.5)
                Text(name).font(.system(size: 11, weight: .semibold)).opacity(0.5)
                Text("omitted (timing)").font(.system(size: 11)).italic().opacity(0.5)
            }
        case .present(let value):
            HStack(spacing: 6) {
                Text(icon).font(.system(size: 12))
                Text(name).font(.system(size: 11, weight: .semibold))
                Text(valueFormatter(value))
                    .font(.system(size: 11, design: .monospaced))
                    .opacity(0.8)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Destination footer

    private var destinationFooter: some View {
        HStack(spacing: 6) {
            Text("→ Sending to:")
                .font(.system(size: 10))
                .opacity(0.7)
            Text(destinationText)
                .font(.system(size: 10, weight: .semibold))
            Text(destinationIcon)
                .font(.system(size: 10))
        }
    }

    private var destinationText: String {
        switch payload.destination {
        case .local(let label): return "\(label) (local)"
        case .cloud(let label): return "\(label) (cloud)"
        }
    }

    private var destinationIcon: String {
        switch payload.destination {
        case .local: return "🟢"
        case .cloud: return "🟡"
        }
    }

    private var backgroundColor: Color {
        switch payload.destination {
        case .local: return Color(red: 0.85, green: 0.95, blue: 0.85).opacity(0.95)
        case .cloud: return Color(red: 1.0, green: 0.92, blue: 0.65).opacity(0.95)
        }
    }

    // MARK: - Helpers

    private func truncate(_ s: String, max: Int) -> String {
        if s.count <= max { return s }
        return String(s.prefix(max)) + "..."
    }

    private func formatTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
}
```

- [ ] **Step 2: Build**

```bash
make local 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add VoiceInk/Views/Recorder/PrivacyHUDView.swift
git commit -m "feat(privacy-hud): add PrivacyHUDView SwiftUI

Renders a PrivacyPayload as a small floating card. Each
ContextField case has its own visual treatment:
  - .disabled / .empty   → row not rendered
  - .pending             → row with spinner + 'identifying...'
  - .omitted             → row faded + 'omitted (timing)'
  - .present(T)          → row with truncated value

Destination footer shows provider label + cloud/local indicator
with matching background tint (yellow for cloud, green for local).

Part of OPA-111."
```

---

## Task 12: PrivacyHUDPanel + PrivacyHUDWindowManager + lifecycle wiring

**Files:**
- Create: `VoiceInk/Views/Recorder/PrivacyHUDPanel.swift`
- Create: `VoiceInk/Views/Recorder/PrivacyHUDWindowManager.swift`
- Modify: `VoiceInk/VoiceInk.swift` (app entry point — instantiate the manager)

- [ ] **Step 1: Create the panel**

Create `VoiceInk/Views/Recorder/PrivacyHUDPanel.swift`:

```swift
import SwiftUI
import AppKit

/// Floating panel that hosts PrivacyHUDView. Mirrors MiniRecorderPanel's style:
/// transparent, non-key, floating level, joins all spaces.
class PrivacyHUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        configurePanel()
    }

    private func configurePanel() {
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovable = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
    }
}
```

- [ ] **Step 2: Create the window manager**

Create `VoiceInk/Views/Recorder/PrivacyHUDWindowManager.swift`:

```swift
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
```

- [ ] **Step 3: Instantiate at app init**

Open `VoiceInk/VoiceInk.swift`. Find where existing window managers / coordinators are created (look for similar lines instantiating `NotchWindowManager` or `MiniRecorderPanel`). Add an `@StateObject` or `@State` private property for `PrivacyHUDWindowManager`, initialized with the same `AIEnhancementService` instance the rest of the app uses.

Concrete addition (adapt to existing app entry pattern — likely in the `App` body or a top-level `@main` struct):

```swift
@StateObject private var privacyHUDManager: PrivacyHUDWindowManager

init() {
    // ... existing init ...
    let service = /* ... however AIEnhancementService is currently obtained ... */
    _privacyHUDManager = StateObject(wrappedValue: PrivacyHUDWindowManager(enhancementService: service))
}
```

If the existing pattern doesn't use `init()` for this, attach the manager to the same scope as `NotchWindowManager` (engine init, etc.). The exact pattern depends on what's already there — read `VoiceInk.swift` first and follow precedent.

- [ ] **Step 4: Build**

```bash
make local 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Manual smoke test**

```bash
make relaunch
```

Push-to-talk: the HUD should appear above MiniRecorder (or below Notch). Release: HUD disappears. If not, debug observation wiring — `enhancementService.$currentPrivacyPayload` must publish on the main queue.

- [ ] **Step 6: Commit**

```bash
git add VoiceInk/Views/Recorder/PrivacyHUDPanel.swift \
       VoiceInk/Views/Recorder/PrivacyHUDWindowManager.swift \
       VoiceInk/VoiceInk.swift
git commit -m "feat(privacy-hud): wire NSPanel + lifecycle

PrivacyHUDPanel is a transparent floating NSPanel matching the
existing MiniRecorderPanel style. PrivacyHUDWindowManager observes
currentPrivacyPayload — when non-nil it shows / updates the panel
at the PositionedFrame; when nil it hides.

Wired into VoiceInk.swift app init alongside the other window
managers.

Part of OPA-111."
```

---

## Task 13: ESC global hotkey cancel handler

**Files:**
- Create: `VoiceInk/Shortcuts/EscapeCancelHandler.swift`
- Modify: `VoiceInk/Transcription/Engine/VoiceInkEngine.swift` (register / unregister in toggleRecord)

- [ ] **Step 1: Create the handler**

Create `VoiceInk/Shortcuts/EscapeCancelHandler.swift`:

```swift
import AppKit

/// Captures global ESC keypress during recording. ESC triggers a full cancel:
/// recording stops, audio buffer discarded, no transcribe, no LLM call.
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
```

Note: `addGlobalMonitorForEvents` listens for events sent to OTHER apps (VoiceInk doesn't have focus during push-to-talk). It doesn't intercept — the other app still gets the ESC. That's acceptable: pressing ESC in most apps is harmless (closes dialogs, deselects). If interception is needed later, add a parallel `addLocalMonitorForEvents` returning nil.

- [ ] **Step 2: Wire into VoiceInkEngine**

In `VoiceInkEngine.swift`, add a property:

```swift
private lazy var escapeCancelHandler: EscapeCancelHandler = EscapeCancelHandler { [weak self] in
    await self?.cancelRecording()
}
```

In the record-start branch of `toggleRecord()` (after recording state becomes `.recording` — around line 170), call:

```swift
self.escapeCancelHandler.register()
```

In both the record-end branch (where state transitions out of `.recording`) and `cancelRecording()` (line 304), call:

```swift
self.escapeCancelHandler.unregister()
```

(Add the unregister BEFORE the actual cancel logic in `cancelRecording`, so ESC pressed during the cancel doesn't re-trigger.)

- [ ] **Step 3: Build**

```bash
make local 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Manual smoke test**

```bash
make relaunch
```

Push-to-talk → speak → press ESC mid-recording. Expected:
- Recording stops immediately
- No paste happens
- No network request (verify with Charles / Proxyman if needed, or just check that no enhanced output appears)

- [ ] **Step 5: Commit**

```bash
git add VoiceInk/Shortcuts/EscapeCancelHandler.swift \
       VoiceInk/Transcription/Engine/VoiceInkEngine.swift
git commit -m "feat(privacy-hud): ESC during recording = cancel

EscapeCancelHandler registers a global NSEvent monitor on
recording start and unregisters on end / cancel. ESC pressed
anywhere during recording calls engine.cancelRecording() — audio
buffer discarded, no transcribe, no LLM call, no paste.

Owner's mental model: 'release hotkey = commit, ESC = abort'.
Uses global (not local) monitor so VoiceInk doesn't need keyboard
focus to catch ESC.

Part of OPA-111 (Q3)."
```

---

## Task 14: Verify cloud / local visual differentiation

**Files:** dog-food test — no code changes (the colors are already wired in Task 11)

- [ ] **Step 1: Build and launch with current default provider (cloud)**

```bash
make dev
```

Open Settings → AI Models → select Anthropic / OpenAI / Groq as enhancement provider. Push-to-talk. HUD background should be yellow-ish, footer text "Claude (cloud) 🟡" or similar.

- [ ] **Step 2: Switch to Ollama and verify**

In Settings → switch enhancement provider to Ollama (assumes Ollama is running locally; if not, install: `brew install ollama && ollama serve & ollama pull llama3.2`).

Push-to-talk again. HUD background should be green-ish, footer "Ollama (local) 🟢".

- [ ] **Step 3: If colors don't differ, debug**

Possible issues:
- `aiService.currentBaseURL` returning Anthropic URL even for Ollama — check `AIService.swift` for the property's implementation
- `PrivacyDestination.detect()` not recognizing the host — print baseURL.host in `assemblePrivacyPayload()` and compare

Fix in `assemblePrivacyPayload()` or `AIService.swift` as needed.

- [ ] **Step 4: Commit any fixes**

```bash
git add <fixed files>
git commit -m "fix(privacy-hud): correct local/cloud destination detection"
```

(Skip if no fix needed.)

---

## Task 15: CLAUDE.md updates

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update "Known privacy gap" section (around lines 64-71)**

Find the existing block in CLAUDE.md that begins "**Selected text is silently included...**". Replace it with:

```markdown
### Closed privacy gaps (fork-specific, no longer present)

**Selected text silent inclusion (closed by OPA-111)** — previously selected text was sent on every LLM call if Accessibility was granted, with no toggle / preview / confirmation. Now:
- Capture happens at record-start (not send-time), so the locked snapshot is what gets sent
- Privacy HUD displays the captured value before send (`docs/superpowers/specs/2026-05-22-privacy-hud-design.md`)
- New global toggle `useSelectedTextContext` (Settings → AI Models → Enhancement panel) defaults ON for backwards compat
- ESC during recording cancels everything (no LLM call)

**Custom vocabulary silent inclusion (closed by OPA-111)** — similar fix; new toggle `useCustomVocabularyContext`.
```

- [ ] **Step 2: Add Append-only log entry (end of file)**

Append:

```markdown
- **2026-05-22**: OPA-111 / OPA-112 / OPA-113 — Privacy HUD landed. Capture-at-record-start architecture: selected text + custom vocabulary moved from send-time fetch to record-start capture, alongside clipboard / screen / system context. New `PrivacyHUDPanel` floats adjacent to active recorder (MiniRecorder above / Notch below), shows every field about to be sent, ESC cancels mid-recording. System context (time / timezone / day-of-week / locale) bundled as `<SYSTEM_CONTEXT>` in system message — Assistant Mode can now answer "what time is it". Two new global toggles (`useSelectedTextContext`, `useCustomVocabularyContext`) close the previous silent-inclusion gap. `getSystemMessage()` reads captured properties first with on-demand fallback so HUD failures don't break enhance pipeline. Spec: `docs/superpowers/specs/2026-05-22-privacy-hud-design.md`. Plan: `docs/superpowers/plans/2026-05-22-privacy-hud.md`.
```

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: close OPA-111/112/113 in CLAUDE.md

Mark selected-text and custom-vocabulary silent-inclusion as
closed; add Append-only log entry recording the divergence in
capture timing (record-start instead of send-time) and the new
global toggles."
```

---

## Task 16: Final dog-food verification + Linear status updates

**Files:** dog-food testing — checklist from spec section 8.4

- [ ] **Step 1: Rebuild and relaunch**

```bash
make dev
```

- [ ] **Step 2: Run through the dog-food checklist**

For each, verify and tick:

- [ ] MiniRecorder mode: HUD appears above the recorder during recording
- [ ] Switch to Notch mode in Settings → restart → HUD appears below the notch
- [ ] OPA-107 three test recordings (`~/Downloads/voicetwink-spike/sample{1,2,3}.m4a` — re-record if cleared earlier) — manually playback while speaking: HUD content matches the eventual LLM payload (inspect via `lastSystemMessageSent` debugger property if needed)
- [ ] No text selected anywhere → push-to-talk → Selected row not rendered in HUD
- [ ] Empty clipboard → push-to-talk → Clipboard row not rendered
- [ ] Copy a fake API key like `sk-abc123def456` → push-to-talk → Clipboard row shows the truncated raw value (no masking — Q6 chose raw display)
- [ ] Settings → turn off Screen Context → push-to-talk → Screen row not rendered
- [ ] Settings → turn on Screen Context → push-to-talk → release within 300ms → HUD's Screen row shows "omitted (timing)"
- [ ] ESC mid-recording → recording stops, no paste, no network egress (verify with `tcpdump -i any -nn host api.anthropic.com` or Charles)
- [ ] Switch enhancement provider from Anthropic to Ollama → HUD background green, footer "Ollama (local) 🟢"
- [ ] Switch back to Claude → HUD background yellow, footer "Claude (cloud) 🟡"
- [ ] Disable all global toggles in Settings → push-to-talk → HUD shows only Time + Destination footer (no context rows)
- [ ] OPA-108 zh-TW: select "Chinese (Taiwan)" → push-to-talk Mandarin → output still uses繁體中文 with Taiwan vocabulary (existing seed prompt still works)
- [ ] Assistant Mode: ask "現在幾點？" → LLM answers with current time (OPA-113 verified)

- [ ] **Step 3: Fix any failures**

For each failed item, debug and commit individual fixes:

```bash
git add <fixed files>
git commit -m "fix(privacy-hud): <specific issue>"
```

- [ ] **Step 4: Update Linear**

Mark these issues done in Linear:

- OPA-111 → Done with comment summarizing what shipped
- OPA-112 → Done with comment linking to the spec + plan
- OPA-113 → Done with comment noting it was bundled with OPA-111

Unblock OPA-114 (Action Mode research) — remove the `blockedBy` relationship since OPA-111 + OPA-112 are now done.

(Use Linear MCP tools `mcp__linear-server__save_issue` and `mcp__linear-server__save_comment`.)

- [ ] **Step 5: Final commit if checklist required fixes**

If everything passes on the first run, no commit needed in this step. Otherwise:

```bash
git log --oneline -20   # review the implementation history
```

---

## Done definition

When all 16 tasks above are checked off and the dog-food checklist passes:

- [ ] `make local` builds cleanly
- [ ] `make dev` relaunches with HUD visible during recording
- [ ] All Linear issues (OPA-111 / OPA-112 / OPA-113) marked Done
- [ ] OPA-114 unblocked
- [ ] CLAUDE.md reflects the new state
- [ ] Owner has signed off on the dog-food checklist
