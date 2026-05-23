# Simulate Typing Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a global Settings toggle that swaps the existing paste pipeline with per-character `CGEventKeyboardSetUnicodeString` injection, bypassing IME and force-disabling AutoSend, so transcripts can be reviewed/edited inline inside Claude Code CLI before manual Enter.

**Architecture:** Branch inside `CursorPaster.performPasteSession` reads the new UserDefault `simulateTypingInsteadOfPaste`. When ON, route to new `typeAtCursor()` (loops over the string, posts one keyDown/keyUp pair per character with 5ms inter-char delay, attaches the unicode via `keyboardSetUnicodeString`). One UI Toggle in the existing `Recording Feedback` section, one gate in `TranscriptionPipeline` to skip AutoSend when typing mode is ON. No `VoiceInkEngine` callsite changes.

**Tech Stack:** Swift / AppKit / Carbon (CGEvent API) / SwiftUI (`@AppStorage` + `Toggle`)

**Linear:** [OPA-115](https://linear.app/opass/issue/OPA-115)
**Spec:** `docs/superpowers/specs/2026-05-24-simulate-typing-mode-design.md`

**Branch:** `feat/simulate-typing-mode`

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `VoiceInk/AppDefaults.swift` | Registered defaults dictionary | Add one entry: `"simulateTypingInsteadOfPaste": false` |
| `VoiceInk/CursorPaster.swift` | Owns the "put transcript at cursor" mechanism | Add `typeAtCursor()` private method + branch in `performPasteSession` |
| `VoiceInk/Transcription/Engine/TranscriptionPipeline.swift` | Orchestrates transcribe → paste → AutoSend flow | Add `simulateTyping` UserDefault read + `&& !simulateTyping` gate on the AutoSend block (line 231) |
| `VoiceInk/Views/Settings/SettingsView.swift` | Settings panel UI | Add `@AppStorage` property + Toggle row inside `Recording Feedback` section |
| `CLAUDE.md` | Append-only fork decision log | Add one bullet after manual smoke test passes |

**Why this decomposition:**
- All paste/typing mechanism lives in `CursorPaster.swift` (cohesive, follows the file's existing scope).
- AutoSend gate lives in the single callsite that fires it (`TranscriptionPipeline.swift:231`), not in `CursorPaster`. Reason: AutoSend is a pipeline-level concern, not a paste-mechanism concern. Mixing them would couple `CursorPaster` to `PowerModeManager`.
- No new files. Everything fits inside existing files following established patterns (other paste-related toggles like `useAppleScriptPaste` already live in the same locations).

## Testing approach

**No unit tests.** The codebase has zero unit tests for `CursorPaster`, `TranscriptionPipeline`, or the settings UI — these depend on system-level CGEvent posting, AX permission, UserDefaults, and SwiftUI state, all of which require infrastructure that doesn't exist in this repo. Adding test scaffolding for this feature alone is out of scope (spec §9). Verification is by `make local` build + manual smoke matrix (spec §9 manual tests, captured below in Task 5).

This is the established pattern — privacy HUD landed the same way (no unit tests, manual smoke).

## Convention notes for the implementer

- **`make local` builds to `/Applications/VoiceInk.app`** via Personal Team signing. Requires `.local-team` file (gitignored) with Team ID — owner already has this set up.
- **`make dev` = `make local && make relaunch`** — preferred for daily iteration. Quits the running app and relaunches the fresh build.
- **Never run `brew install --cask voiceink`** or any pre-built upstream binary — fork mission rule (see CLAUDE.md).
- **Don't auto-commit CLAUDE.md** until manual smoke test passes (the log entry confirms results, not just code landing).
- **Commit messages:** project pattern is short imperative lowercase, optional scope prefix. Recent commits: `fix(privacy-hud): widen HUD 380 → 700pt`, `docs(OPA-115): add spec`. Stay terse.
- **Branch name:** `feat/simulate-typing-mode` (matches prior pattern `feat/privacy-hud`).

---

### Task 1: Register UserDefault and create branch

**Files:**
- Modify: `VoiceInk/AppDefaults.swift:5-56` (add one line to register dict)

- [ ] **Step 1: Create feature branch**

Run:
```bash
git checkout -b feat/simulate-typing-mode
```
Expected: `Switched to a new branch 'feat/simulate-typing-mode'`

- [ ] **Step 2: Add the UserDefault registration**

Edit `VoiceInk/AppDefaults.swift`. In the `Clipboard` group (lines 10-13), add a new line after `"useAppleScriptPaste": false,`:

Before:
```swift
            // Clipboard
            "restoreClipboardAfterPaste": true,
            "clipboardRestoreDelay": 2.0,
            "useAppleScriptPaste": false,
```

After:
```swift
            // Clipboard
            "restoreClipboardAfterPaste": true,
            "clipboardRestoreDelay": 2.0,
            "useAppleScriptPaste": false,
            "simulateTypingInsteadOfPaste": false,
```

- [ ] **Step 3: Verify build still succeeds**

Run:
```bash
make check && make local
```
Expected: build completes, `Build complete! App saved to: /Applications/VoiceInk.app`.

- [ ] **Step 4: Commit**

```bash
git add VoiceInk/AppDefaults.swift
git commit -m "feat(OPA-115): register simulateTypingInsteadOfPaste default (false)"
```

---

### Task 2: Implement `typeAtCursor()` and wire branch in `performPasteSession`

**Files:**
- Modify: `VoiceInk/CursorPaster.swift` (add branch at top of `performPasteSession` line 47, add new `typeAtCursor()` method in new `// MARK: - Simulated typing` section)

- [ ] **Step 1: Add branch at top of `performPasteSession`**

In `VoiceInk/CursorPaster.swift`, locate `performPasteSession` (line 46-75). Add the branch as the first statement of the function body.

Before (lines 46-50):
```swift
    @MainActor
    private static func performPasteSession(_ text: String) async -> PasteResult {
        let pasteboard = NSPasteboard.general
        let shouldRestoreClipboard = UserDefaults.standard.bool(forKey: "restoreClipboardAfterPaste")
        let savedContents = shouldRestoreClipboard ? snapshotClipboard(from: pasteboard) : []
```

After:
```swift
    @MainActor
    private static func performPasteSession(_ text: String) async -> PasteResult {
        if UserDefaults.standard.bool(forKey: "simulateTypingInsteadOfPaste") {
            return await typeAtCursor(text)
        }

        let pasteboard = NSPasteboard.general
        let shouldRestoreClipboard = UserDefaults.standard.bool(forKey: "restoreClipboardAfterPaste")
        let savedContents = shouldRestoreClipboard ? snapshotClipboard(from: pasteboard) : []
```

- [ ] **Step 2: Add `// MARK: - Simulated typing` section with `typeAtCursor()`**

In `VoiceInk/CursorPaster.swift`, insert the following new section **before** the existing `// MARK: - Auto Send Keys` line (which is line 212 in the current file). The new section adds one private static method and the per-character delay constant.

Insert this entire block:

```swift
    // MARK: - Simulated typing

    private static let typingInterCharDelay: TimeInterval = 0.005

    @MainActor
    private static func typeAtCursor(_ text: String) async -> PasteResult {
        guard AXIsProcessTrusted() else {
            logger.error("Accessibility permission required for simulated typing")
            return .commandNotPosted
        }

        let source = CGEventSource(stateID: .privateState)
        for char in text {
            let str = String(char)
            let utf16 = Array(str.utf16)

            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                logger.error("Failed to create typing key events for char: \(str, privacy: .public)")
                continue
            }

            utf16.withUnsafeBufferPointer { buf in
                if let base = buf.baseAddress {
                    keyDown.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: base)
                    keyUp.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: base)
                }
            }

            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)

            await wait(typingInterCharDelay)
        }

        return .commandPosted
    }

```

Notes for the implementer:
- `logger`, `wait(_:)`, and `PasteResult` are all already defined in this file (`logger` line 9; `wait` line 206-210; `PasteResult` line 11-18). No new imports needed.
- `AXIsProcessTrusted()` is from `import ApplicationServices` which is transitively imported via `AppKit` (already at line 2). Confirmed by `pasteFromClipboard` line 176 using the same call.
- `CGEvent` and `CGEventSource` are from CoreGraphics (in `AppKit`). Same as existing CGEvent paste path.
- Per-character grapheme iteration via `for char in text` is intentional: Swift `Character` is a grapheme cluster (handles ZWJ emoji, accents, surrogate pairs correctly). `String(char).utf16` then produces the UTF-16 code units `CGEventKeyboardSetUnicodeString` expects.
- 5ms = 5_000_000 nanoseconds; `wait(_:)` takes a `TimeInterval` (seconds), so `0.005`.

- [ ] **Step 3: Build**

Run:
```bash
make local
```
Expected: build completes, `Build complete! App saved to: /Applications/VoiceInk.app`. If Swift complains about unused symbols (`typingInterCharDelay`, `typeAtCursor`), that's wrong — the branch in Step 1 calls them. Re-check Step 1's edit landed.

- [ ] **Step 4: Commit**

```bash
git add VoiceInk/CursorPaster.swift
git commit -m "feat(OPA-115): add typeAtCursor + branch in performPasteSession"
```

---

### Task 3: Gate AutoSend when typing mode is ON

**Files:**
- Modify: `VoiceInk/Transcription/Engine/TranscriptionPipeline.swift:228-237` (read UserDefault, add gate condition)

- [ ] **Step 1: Add the gate**

In `VoiceInk/Transcription/Engine/TranscriptionPipeline.swift`, locate the AutoSend block at line 228-237. Read the new UserDefault and gate the condition.

Before (lines 228-237):
```swift
            _ = await CursorPaster.startPasteAtCursor(pastedText).value
            let autoSendKey = PowerModeManager.shared.currentActiveConfiguration?.autoSendKey
            SoundManager.shared.playStopSound()
            await restorePromptDetectionSettingsAndDismiss {
                if let autoSendKey, autoSendKey.isEnabled {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        CursorPaster.performAutoSend(autoSendKey)
                    }
                }
            }
```

After:
```swift
            _ = await CursorPaster.startPasteAtCursor(pastedText).value
            let autoSendKey = PowerModeManager.shared.currentActiveConfiguration?.autoSendKey
            let simulateTyping = UserDefaults.standard.bool(forKey: "simulateTypingInsteadOfPaste")
            SoundManager.shared.playStopSound()
            await restorePromptDetectionSettingsAndDismiss {
                if let autoSendKey, autoSendKey.isEnabled, !simulateTyping {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        CursorPaster.performAutoSend(autoSendKey)
                    }
                }
            }
```

Note: read `simulateTyping` **outside** the `restorePromptDetectionSettingsAndDismiss` closure so the captured value is determined at the same moment as `autoSendKey`. Reading it inside the closure would still work but is racier (the user could conceivably toggle the setting between paste and the 500ms delayed AutoSend, which is silly but inconsistent).

- [ ] **Step 2: Build**

Run:
```bash
make local
```
Expected: build completes successfully.

- [ ] **Step 3: Commit**

```bash
git add VoiceInk/Transcription/Engine/TranscriptionPipeline.swift
git commit -m "feat(OPA-115): skip AutoSend when typing mode is on"
```

---

### Task 4: Add Settings UI Toggle

**Files:**
- Modify: `VoiceInk/Views/Settings/SettingsView.swift:23` (add `@AppStorage`)
- Modify: `VoiceInk/Views/Settings/SettingsView.swift:198-203` (add Toggle row after existing `useAppleScriptPaste` toggle)

- [ ] **Step 1: Add the `@AppStorage` property**

In `VoiceInk/Views/Settings/SettingsView.swift`, add a new `@AppStorage` declaration directly after the existing `useAppleScriptPaste` declaration (line 23).

Before (lines 21-23):
```swift
    @AppStorage("restoreClipboardAfterPaste") private var restoreClipboardAfterPaste = true
    @AppStorage("clipboardRestoreDelay") private var clipboardRestoreDelay = 2.0
    @AppStorage("useAppleScriptPaste") private var useAppleScriptPaste = false
```

After:
```swift
    @AppStorage("restoreClipboardAfterPaste") private var restoreClipboardAfterPaste = true
    @AppStorage("clipboardRestoreDelay") private var clipboardRestoreDelay = 2.0
    @AppStorage("useAppleScriptPaste") private var useAppleScriptPaste = false
    @AppStorage("simulateTypingInsteadOfPaste") private var simulateTypingInsteadOfPaste = false
```

- [ ] **Step 2: Add the Toggle row**

In `VoiceInk/Views/Settings/SettingsView.swift`, locate the `// AppleScript Paste` toggle (lines 197-203). Add a new toggle directly after it, before the closing `}` of the `Section("Recording Feedback")` (line 204).

Before (lines 197-204):
```swift
                // AppleScript Paste
                Toggle(isOn: $useAppleScriptPaste) {
                    HStack(spacing: 4) {
                        Text("Use AppleScript Paste")
                        InfoTip("Enable this if pasting doesn't work with your keyboard layout (e.g. Neo2). Uses AppleScript instead of simulated key events.")
                    }
                }
            }
```

After:
```swift
                // AppleScript Paste
                Toggle(isOn: $useAppleScriptPaste) {
                    HStack(spacing: 4) {
                        Text("Use AppleScript Paste")
                        InfoTip("Enable this if pasting doesn't work with your keyboard layout (e.g. Neo2). Uses AppleScript instead of simulated key events.")
                    }
                }

                // Simulate Typing
                Toggle(isOn: $simulateTypingInsteadOfPaste) {
                    HStack(spacing: 4) {
                        Text("Simulate Typing Instead of Paste")
                        InfoTip("Types each character as a simulated key event instead of pasting. Slower for long text, but avoids paste-collapse in apps like Claude Code CLI. Bypasses IME via direct Unicode injection. Note: Auto Send is disabled in this mode — press Enter manually after reviewing.")
                    }
                }
            }
```

- [ ] **Step 3: Build and relaunch the app**

Run:
```bash
make dev
```
Expected: build completes, app relaunches. Open Settings (menu bar icon → Settings) → scroll to `Recording Feedback` section → confirm the new "Simulate Typing Instead of Paste" toggle appears directly below "Use AppleScript Paste", with the InfoTip popover showing the description above. Toggle it on and off once to confirm it persists across app relaunch (`make dev` again, verify state restored).

- [ ] **Step 4: Commit**

```bash
git add VoiceInk/Views/Settings/SettingsView.swift
git commit -m "feat(OPA-115): add Simulate Typing settings toggle"
```

---

### Task 5: Manual smoke test + close out

**Files:**
- Modify: `CLAUDE.md` (append one log entry at the end of the "Append-only log" section)

This task is the actual verification of whether the probe succeeded. If it fails, document the failure mode and decide next step before landing the CLAUDE.md entry.

- [ ] **Step 1: Confirm clean build**

Run:
```bash
make dev
```
Expected: app relaunches with all four code changes from Tasks 1-4 live.

- [ ] **Step 2: Verify toggle OFF preserves existing behavior (regression check)**

With toggle OFF (default):
- Settings → Recording Feedback → confirm "Simulate Typing Instead of Paste" is OFF
- Open any text field (e.g., a new TextEdit document)
- Trigger recording, say a short sentence in English, release
- Expected: transcript appears in TextEdit via instant paste (existing behavior)
- If you have a Power Mode with AutoSend Enter configured for any app: confirm AutoSend still fires

- [ ] **Step 3: Verify toggle ON in Claude Code CLI (primary success criterion)**

With toggle ON:
- Settings → Recording Feedback → enable "Simulate Typing Instead of Paste"
- Open Ghostty, attach to tmux session, run `claude` (Claude Code CLI)
- Trigger recording, say a paragraph in zh-TW that's at least 100 characters (e.g., 「我想要請你幫我看一下這段程式碼，重點是看有沒有可以簡化的地方，特別是迴圈的部分」)
- Release recording, wait for transcript
- Expected — primary success: transcript appears character-by-character in Claude CC's input, **without** the `[Pasted text +N lines]` collapse. The text is editable inline. No Enter fires automatically.
- Expected — secondary verification: typing pace is visible but not painful (~5ms/char = ~2.5s for 500 chars).
- **If `[paste]` collapse still happens**: STOP. The probe has failed at its primary goal. Don't write the CLAUDE.md log yet — instead, jump to "If probe fails" below.

- [ ] **Step 4: Verify zh-TW IME bypass**

Still with toggle ON:
- Switch to 注音 input method (Bopomofo)
- Open a SwiftUI text field (e.g., Notes app, a new note)
- Trigger recording, say a sentence in zh-TW
- Expected: the recognized zh-TW characters appear directly in the field as fully-formed text. The 注音 IME does NOT intercept the injection (no Bopomofo phonetic symbols appear; no IME composition window opens for the injected text).
- Switch back to your usual input method when done.

- [ ] **Step 5: Verify AutoSend is suppressed (even when configured)**

Still with toggle ON:
- Open Power Mode settings, pick or create a Power Mode bound to a test app (e.g., Slack)
- Set AutoSend to Enter for that Power Mode
- Open Slack (or whatever app you bound), focus a message input
- Trigger recording, speak a short message, release
- Expected: text types out, but Enter is **not** posted automatically. The message stays in the compose box. You press Enter manually to send.
- Reset the Power Mode if it was a test rule.

- [ ] **Step 6: Verify Emoji and mixed-script handling**

Still with toggle ON:
- In a Notes / TextEdit field, trigger recording and say something that produces an emoji (e.g., "I think this is great 👍" if your prompt generates emoji), or a sentence mixing Chinese + English ("我覺得這個 implementation 很 elegant")
- Expected: emoji renders correctly (single emoji, not broken surrogate halves); mixed-script transition is seamless; no character dropping.

- [ ] **Step 7: Append CLAUDE.md log entry**

If Steps 2-6 all pass: edit `CLAUDE.md`, scroll to the "Append-only log" section at the bottom, and add a new bullet at the end using today's date. The entry should briefly state the feature, what it does, where the toggle lives, and the probe outcome.

Use the existing entries (the OPA-108, build signing, and OPA-111/112/113 entries) as the style reference — Traditional Chinese, factual, includes which files changed and the why. Example structure:

```markdown
- **2026-05-24**: OPA-115 — 新增 "Simulate Typing Instead of Paste" Settings toggle（Recording Feedback section, default OFF）。打開時 `CursorPaster.performPasteSession` 走新增的 `typeAtCursor()` 路徑，逐字用 `CGEventKeyboardSetUnicodeString` 注入（5ms inter-char delay），繞過 IME（注音輸入法 active 時不被攔截）。同步在 `TranscriptionPipeline.swift:228` AutoSend 觸發點加 gate：typing mode ON 時強制不發 Enter，使用者先檢視 transcript 再手動送出。動機：解決 Claude Code CLI 對大段 paste 自動收摺成 `[Pasted text +N]` 導致無法 inline 編輯的問題。改動：`CursorPaster.swift`、`TranscriptionPipeline.swift`、`SettingsView.swift`、`AppDefaults.swift`。Probe 結果：[在此記實測結果 — Claude CC 是否確實 inline 顯示、是否仍有摺疊、有沒有掉字等]。
```

Replace the bracketed `[在此記實測結果...]` placeholder with the actual observation from Steps 3-6 before committing.

- [ ] **Step 8: Commit the log entry**

```bash
git add CLAUDE.md
git commit -m "docs(OPA-115): log Simulate Typing Mode probe outcome"
```

- [ ] **Step 9: Merge to main**

```bash
git checkout main
git merge --no-ff feat/simulate-typing-mode -m "Merge branch 'feat/simulate-typing-mode' — OPA-115"
```
Expected: merge commit lands on main. No push (project rule: never push without explicit user ask).

- [ ] **Step 10: Update Linear OPA-115 to Done**

Use the Linear MCP `save_issue` tool with `id: "OPA-115"` and `state: "Done"`. Optionally add a short comment summarizing the probe outcome (success / partial / failed) and linking the merge commit SHA.

---

## If probe fails (Step 3 shows `[paste]` collapse still happens)

This is acceptable per the spec — owner explicitly said "我也不確定能不能解決問題". Don't force success.

1. **Do not** write the CLAUDE.md log claiming victory.
2. **Do** write a CLAUDE.md log entry honestly recording the failure mode (which app, what was observed, your hypothesis why — e.g., "Ghostty wraps all CGEvent injections in bracketed paste sequences regardless of mechanism").
3. **Keep** the toggle and the implementation merged — it's still useful for IME-bypass typing in other apps and the code is small.
4. **Update OPA-115 Linear status:** instead of `Done`, leave it `In Progress` or move to `Canceled` (probe completed, conclusion negative). Add a comment with the observed failure and link any follow-up issues (e.g., a new ticket for trying the preview-edit HUD direction discussed in the brainstorm).
5. **Mention to owner** at the end of execution: "Probe completed, result was [X]. Toggle is shipped but doesn't solve the original Claude CC problem. Next step would be [Y]."

---

## Self-Review (done at plan-writing time)

**Spec coverage:**
- Spec §3 behavior matrix → Tasks 1 (default), 2 (typing path), 3 (AutoSend gate), 4 (UI) ✓
- Spec §4 architecture decision (branch in CursorPaster) → Task 2 ✓
- Spec §5 typing mechanism code → Task 2 Step 2 (verbatim) ✓
- Spec §6 AutoSend gate location and code → Task 3 (verbatim) ✓
- Spec §7 Settings UI location + InfoTip text → Task 4 (verbatim) ✓
- Spec §8 edge cases → covered by manual test matrix in Task 5 (AX permission via Step 1 build check, mid-flow cancel not specially tested — same as paste, accepted by spec) ✓
- Spec §9 testing approach (manual smoke, no unit tests) → Task 5 ✓
- Spec §10 open questions → not actionable in plan; deferred ✓
- Spec §11 file change list → exact match ✓

**Placeholder scan:** One intentional placeholder in Task 5 Step 7 — `[在此記實測結果...]` — meant to be filled by the implementer at smoke-test time with actual observations. Not a plan failure; it's the point of the task.

**Type consistency:**
- `simulateTypingInsteadOfPaste` (UserDefault key) used identically in Tasks 1, 2, 3, 4 ✓
- `typingInterCharDelay` (Task 2 constant) only used inside `typeAtCursor` (same task) ✓
- `typeAtCursor(_:)` signature `async -> PasteResult` matches existing `pasteFromClipboard()` signature for consistency with `performPasteSession` return type ✓
- `wait(_:)` reuses existing helper at line 206-210, signature `TimeInterval -> Void async` ✓
