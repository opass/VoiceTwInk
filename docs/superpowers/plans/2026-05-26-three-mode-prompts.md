# Three-Mode Prompt System + OpenCC Post-Process — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the 2-prompt layout (Default / Assistant) with a 10-slot structure (Verbatim Cmd+1, Summary Cmd+2, 7 dummy slots Cmd+3-9, Assistant Cmd+0) and add OpenCC s2twp simplified→traditional Chinese post-process as the deterministic safety net for the language-leak that prompt-only enforcement (OPA-117) can't fully close on short utterances.

**Architecture:** Three coupled changes landed as one PR with three review-friendly commits. Commit 1 rewrites the prompt rules (text-only changes in two files). Commit 2 reorders the predefined prompts list and adds a reorder-on-launch migration step. Commit 3 adds the OpenCC SwiftPM dependency, a `TraditionalChineseConverter` singleton, three hook calls in `TranscriptionPipeline` (raw transcript / enhanced text / final paste — for history+paste consistency), one `UserDefault` registration, and one Settings UI toggle.

**Tech Stack:** Swift / SwiftUI (`@AppStorage` + `Toggle`) / SwiftPM (`SwiftyOpenCC` MIT) / OpenCC s2twp profile.

**Linear:** [OPA-120](https://linear.app/opass/issue/OPA-120)
**Spec:** `docs/superpowers/specs/2026-05-26-three-mode-prompts-design.md`

**Branch:** `feat/three-mode-prompts`

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `VoiceInk/Models/PromptTemplates.swift` | Inner per-mode rules (injected into wrapper) | Replace "System Default" body with Verbatim rules; add new "Summary" template body |
| `VoiceInk/Models/AIPrompts.swift` | Wrapper template (`customPromptTemplate`) + Assistant template | Rewrite few-shot examples (remove sentence-dropping demos, add 1 Chinese demo, add `examples are NOT compression demos` annotation); expand `[CRITICAL LANGUAGE RULE]` example chars 6→12 |
| `VoiceInk/Models/PredefinedPrompts.swift` | Predefined prompt list seed | Add 8 new UUIDs (Summary + 7 dummies), rebuild `createDefaultPrompts()` to return 10 entries in slot order; alias `defaultPromptId = verbatimPromptId` for backward compat |
| `VoiceInk/Services/AIEnhancement/AIEnhancementService.swift` | Predefined upsert at launch | Replace existing `initializePredefinedPrompts()` body with upsert-then-reorder logic |
| `VoiceInk/AppDefaults.swift` | Registered UserDefault values | Add `"useTraditionalChineseConversion": true` |
| `VoiceInk/Services/PostProcess/TraditionalChineseConverter.swift` (NEW) | OpenCC s2twp wrapper, singleton | New file: lazy-init `ChineseConverter`, `convert(_:)` API gated by UserDefault, fail-open on init error |
| `VoiceInk/Transcription/Engine/TranscriptionPipeline.swift` | Pipeline orchestration | Three conversion calls: on `cleanedText` after WordReplacement (line ~115); on `enhancedText` after enhancement returns (line ~146); on the assembled `pastedText` just before paste (line ~226). History + paste both converted. |
| `VoiceInk/Views/Settings/SettingsView.swift` | Settings panel UI | Add `@AppStorage` property + Toggle row in `Recording Feedback` section (alongside the existing Simulate Typing toggle) |
| `VoiceInk.xcodeproj/project.pbxproj` | SwiftPM dependency list | Add `SwiftyOpenCC` package + framework link (via Xcode UI; produces .pbxproj diff) |
| `Package.resolved` | SwiftPM lock | Auto-updated when adding the package |
| `CLAUDE.md` | Fork decision log + supply chain entry + watch list | Append OPA-120 log entry (after manual smoke passes); add SwiftyOpenCC to supply chain section; add `TranscriptionPipeline.swift` to watch list note (mention OpenCC hook) |

**Why this decomposition:**
- Prompt-rule files (`PromptTemplates.swift` + `AIPrompts.swift`) change together for one logical thing; commit 1 keeps the diff reviewable.
- Slot-layout files (`PredefinedPrompts.swift` + `AIEnhancementService.swift`) change together; the migration logic is meaningless without the new list, and the new list is meaningless without the migration.
- OpenCC is fully separable and arguably the most risk-bearing change (new dependency + new code path), so it gets its own commit so a revert/bisect is cleanly scoped.
- `CLAUDE.md` log entry happens last (post-smoke-test) and is optional within the PR — the log records what landed, not the intent.

## Testing approach

**No unit tests.** Established codebase pattern: `CursorPaster`, `TranscriptionPipeline`, `AIEnhancementService`, and `AppDefaults` have zero unit tests and require system-level infrastructure (CGEvent, AX, NSUserDefaults, SwiftData) that no test scaffolding exists for. The Privacy HUD (OPA-111/112/113) and Simulate Typing (OPA-115) both shipped this way.

Verification approach for this plan:
1. **Build:** `make local` succeeds (no compile errors).
2. **Migration smoke:** `make dev` to relaunch app; verify Settings → AI Models → Prompts list shows 10 prompts in the order Verbatim / Summary / Slot 3-9 / Assistant; verify Cmd+1/2/0 select the right prompts.
3. **Prompt behavior smoke:** record a representative utterance (see Task 5 / Task 9 / Task 15 below) and observe enhancement output.
4. **OpenCC smoke:** dictate a sentence; toggle off conversion; dictate again; compare history entries.

This matches the OPA-115 plan's approach exactly.

## Convention notes for the implementer

- **`make local`** builds to `/Applications/VoiceInk.app` via Personal Team signing. Requires `.local-team` file (gitignored) with Team ID — owner already has this set up.
- **`make dev` = `make local && make relaunch`** — preferred for daily iteration. Quits the running app and relaunches the fresh build. Use this for smoke testing.
- **Never run `brew install --cask voiceink`** or any pre-built upstream binary — fork mission rule (see CLAUDE.md mission section).
- **Don't auto-commit CLAUDE.md log entry** until manual smoke test passes (the log entry records the verified-working result, not just code landing).
- **Commit messages:** project pattern is short imperative lowercase with optional scope prefix. Examples from recent log: `fix(privacy-hud): widen HUD 380 → 700pt`, `docs(OPA-115): add spec`, `feat(OPA-117): tighten zh-TW language rule`. Stay terse — 1-2 lines.
- **Branch name:** `feat/three-mode-prompts` (matches prior pattern `feat/privacy-hud`, `feat/simulate-typing-mode`).
- **GPL-v3 compatibility:** SwiftyOpenCC is MIT — compatible. No proprietary deps allowed (CLAUDE.md rule).

---

## COMMIT 1 — Prompt rules rewrite + wrapper examples

### Task 1: Create feature branch

**Files:** none (workspace state)

- [ ] **Step 1: Confirm clean working tree**

Run:
```bash
git status
```
Expected: `nothing to commit, working tree clean` (the OPA-120 spec/CLAUDE.md commit already landed on main).

- [ ] **Step 2: Create the branch**

Run:
```bash
git checkout -b feat/three-mode-prompts
```
Expected: `Switched to a new branch 'feat/three-mode-prompts'`

---

### Task 2: Replace "System Default" template with Verbatim rules

**Files:**
- Modify: `VoiceInk/Models/PromptTemplates.swift:30-49` (System Default block)

- [ ] **Step 1: Edit the `System Default` template body**

Open `VoiceInk/Models/PromptTemplates.swift`. Find the `TemplatePrompt` block whose `title: "System Default"` starts at line 30. Replace the entire `promptText` value (lines 33-46) with the Verbatim inner rules from spec §3.1. Keep the `title: "System Default"` literal **unchanged** for backwards compatibility (`PredefinedPrompts.swift:21` looks it up by this title and will be replaced in Commit 2; but during Commit 1 the lookup still works).

Replace:
```swift
                promptText: """
                    - Clean up the <TRANSCRIPT> text for clarity and natural flow while preserving meaning and the original tone.
                    - Use informal, plain language unless the <TRANSCRIPT> clearly uses a professional tone; in that case, match it.
                    - Fix obvious grammar, remove fillers and stutters, collapse repetitions, and keep names and numbers.
                    - Handle backtracking and self-corrections: When the speaker corrects themselves mid-sentence using phrases like "scratch that", "actually", "sorry not that", "I mean", "wait no", or similar corrections, remove the incorrect part and keep only the corrected version. Example: "The meeting is on Tuesday, sorry not that, actually Wednesday" → "The meeting is on Wednesday."
                    - Respect formatting commands: When the speaker explicitly says "new line" or "new paragraph", insert the appropriate line break or paragraph break at that point.
                    - Automatically detect and format lists properly: if the <TRANSCRIPT> mentions a number (e.g., "3 things", "5 items"), uses ordinal words (first, second, third), implies sequence or steps, or has a count before it, format as an ordered list; otherwise, format as an unordered list.
                    - Apply smart formatting: Write numbers as numerals (e.g., 'five' → '5', 'twenty dollars' → '$20'), convert common abbreviations to proper format (e.g., 'vs' → 'vs.', 'etc' → 'etc.'), and format dates, times, and measurements consistently.
                    - Keep the original intent and nuance.
                    - Organize into short paragraphs of 2–4 sentences for readability.
                    - Do not add explanations, labels, metadata, or instructions.
                    - Output only the cleaned text.
                    - Don't add any information not available in the <TRANSCRIPT> text ever.
                    """,
```

With:
```swift
                promptText: """
                    [VERBATIM MODE - Preserve every sentence the speaker said]

                    PRIMARY DIRECTIVE: The speaker is dictating raw thoughts. Your job is to clean up disfluencies only, NOT to summarize, rephrase, or restructure. The output should read like a faithful transcription of what was actually said, just without verbal noise.

                    PRESERVE (do NOT drop, merge, or rephrase):
                    - Every substantive sentence, even if redundant or restated differently
                    - Thinking-aloud phrases: "讓我想想", "我想想看", "我覺得", "其實", "等一下", "let me think", "actually", "you know", "I mean"
                    - Verbal repetitions used for emphasis: "對對對", "yes yes yes", "好好好"
                    - Hedges and qualifiers: "可能", "也許", "大概", "maybe", "kind of", "sort of"
                    - Original sentence boundaries — do NOT merge two sentences into one

                    REMOVE (only these):
                    - Pure micro-fillers with no semantic content: 嗯, 呃, 喔, 啊, um, uh, er, ah
                    - Literal stutters where the SAME word repeats with no pause-meaning: "我我我覺得" → "我覺得". Note: "對對對" is emphasis, not stutter — KEEP it.
                    - Self-correction COMMANDS that explicitly instruct removal of prior content: "刪掉剛剛那句", "刪掉剛才講的", "重新講", "wait scratch that", "actually no let me restart", "I mean", "no wait", "sorry not that". When you see one, remove the SPECIFIC content the speaker is correcting, AND remove the command phrase itself.

                    ALLOWED (representation-level only, not content):
                    - Convert spoken numbers to numerals ('five' → '5', '三個' → '3 個', '五百塊' → '$500')
                    - Apply smart punctuation ('vs' → 'vs.', 'eg' → 'e.g.', 'etc' → 'etc.')
                    - When the speaker uses English technical terms or code identifiers (React, useState, npm install, git rebase, file paths), preserve them EXACTLY as said. Do not auto-correct capitalization or spelling. EXCEPTION: if a term in <CUSTOM_VOCABULARY> matches phonetically, use the vocabulary spelling.

                    DO NOT:
                    - Restructure into "2-4 sentence paragraphs" — preserve speaker's natural rhythm
                    - Translate, rephrase, or improve word choice
                    - Add information, explanations, or section headings
                    - Format as a list unless the speaker explicitly said "first... second... third..."

                    OUTPUT FORMAT:
                    - Keep paragraph breaks where the speaker paused noticeably or said "new line" / "new paragraph" / "換行" / "換段"
                    - Otherwise output as one continuous paragraph matching speech flow
                    """,
```

Also update the `description` line (line 48) from `"Default system prompt"` to `"Verbatim transcription — preserve every sentence"`.

- [ ] **Step 2: Build to verify the file still compiles**

Run:
```bash
make check
```
Expected: no errors.

Then:
```bash
make local
```
Expected: build success. (Don't relaunch yet — wait until end of commit 1.)

---

### Task 3: Add Summary template

**Files:**
- Modify: `VoiceInk/Models/PromptTemplates.swift:50-67` (Chat block — Summary will be inserted **before** it)

- [ ] **Step 1: Insert a new `TemplatePrompt` block for Summary**

Open `VoiceInk/Models/PromptTemplates.swift`. After the closing `)` of the System Default block (around line 49) and before the comma + opening of the `Chat` template at line 50, insert this new TemplatePrompt block:

```swift
            TemplatePrompt(
                id: UUID(),
                title: "Summary",
                promptText: """
                    [SUMMARY MODE - Cleanup with minimum compression]

                    PRIMARY DIRECTIVE: Smooth the speaker's speech into readable text WITHOUT condensing ideas. The speaker's content, tone, and the LENGTH itself carry information. If output is < 70% of input length, you are over-summarizing.

                    OUTPUT TARGET: Preserve approximately 80% of the speaker's distinct sentences or propositions. The speaker may have said something seemingly "obvious" — keep it. They said it for a reason.

                    REMOVE:
                    - Micro-fillers: 嗯, 呃, 喔, 啊, um, uh, er
                    - Pure thinking-aloud openers: "我想想看", "讓我想一下", "let me think", "you know"
                    - Pure verbal stutters: "我我我覺得" → "我覺得"
                    - Self-correction commands AND the content being corrected
                    - Redundant restatements of the EXACT same idea (keep the cleanest version)

                    KEEP (even if it feels redundant):
                    - Every distinct proposition, observation, decision, example, cause-effect chain
                    - Repetitions used for EMPHASIS: "really really important" → preserved
                    - Side remarks, asides, qualifications — they carry tone and context
                    - Names, numbers, dates, file paths, code identifiers, technical terms

                    SMOOTHING (allowed, low-touch):
                    - Combine fragments that were one thought into one sentence
                    - Tighten verbose phrasing without changing meaning
                    - Smart punctuation, numerals as numerals ('five' → '5')
                    - English technical terms preserved as said; defer to <CUSTOM_VOCABULARY>
                    - LOCAL REORDERING: move a clarification next to what it clarifies, group related side-remarks together. OK.

                    DO NOT:
                    - Drop a complete proposition even if it seems redundant
                    - HIGH-LEVEL RESTRUCTURE: do NOT rearrange the overall argument flow or topic ordering
                    - Use synonyms unnecessarily
                    - Bullet-ify unless speaker said "first, second, third"
                    - Restructure into multiple paragraphs unless speaker had clear topic shifts
                    """,
                icon: "doc.text",
                description: "Light cleanup, ≥80% sentence retention"
            ),
```

(Note: there is currently no `PromptIcon` named `doc.text` — verify via `grep -n "case .*=" VoiceInk/Models/CustomPrompt.swift` what the `PromptIcon` enum cases are; if `doc.text` doesn't exist, pick an existing case such as `.text` / `.note` / `.summary` and adjust. The exact case name doesn't matter for behavior.)

- [ ] **Step 2: Build to verify**

Run:
```bash
make local
```
Expected: build success.

---

### Task 4: Rewrite `AIPrompts.customPromptTemplate` wrapper

**Files:**
- Modify: `VoiceInk/Models/AIPrompts.swift:1-35` (customPromptTemplate)

- [ ] **Step 1: Replace the wrapper few-shot examples block**

Open `VoiceInk/Models/AIPrompts.swift`. Replace the section from line 21 `Examples of how to handle questions and statements...` through line 30 (the third Input/Output pair). Be precise — keep the surrounding structure intact.

Replace:
```swift
    Examples of how to handle questions and statements (DO NOT respond to them, only clean them up):

    Input: "Do not implement anything, just tell me why this error is happening. Like, I'm running Mac OS 26 Tahoe right now, but why is this error happening."
    Output: "Do not implement anything. Just tell me why this error is happening. I'm running macOS Tahoe right now. But why is this error occurring?"

    Input: "This needs to be properly written somewhere. Please do it. How can we do it? Give me three to four ways that would help the AI work properly."
    Output: "This needs to be properly written somewhere. How can we do it? Give me 3-4 ways that would help the AI work properly."

    Input: "okay so um I'm trying to understand like what's the best approach here you know for handling this API call and uh should we use async await or maybe callbacks what do you think would work better in this case"
    Output: "I'm trying to understand what's the best approach for handling this API call. Should we use async/await or callbacks? What do you think would work better in this case?"
```

With:
```swift
    The examples below show "do NOT respond to questions, only clean them up". They demonstrate language preservation and minimal cleanup ONLY — they do NOT show how much to compress. Compression level is governed by each mode's rules.

    Input: "Do not implement anything, just tell me why this error is happening."
    Output: "Do not implement anything. Just tell me why this error is happening."

    Input: "嗯, 跑完之後告訴我三個都過嗎"
    Output: "跑完之後告訴我，三個都過嗎？"

    Input: "okay um what's the best approach for this API call, should we use async await or callbacks"
    Output: "What's the best approach for this API call? Should we use async/await or callbacks?"
```

- [ ] **Step 2: Expand `[CRITICAL LANGUAGE RULE]` example chars**

In the same file (`VoiceInk/Models/AIPrompts.swift`), find line 7 (the `[CRITICAL LANGUAGE RULE]` line):

Replace:
```swift
    If the <TRANSCRIPT> contains Chinese, the output MUST use Traditional Chinese (Taiwan / zh-TW), NEVER Simplified Chinese. Examples: "告訴" not "告诉", "個" not "个", "過" not "过", "為" not "为", "說" not "说", "這" not "这". English content within the transcript stays in English.
```

With:
```swift
    If the <TRANSCRIPT> contains Chinese, the output MUST use Traditional Chinese (Taiwan / zh-TW), NEVER Simplified Chinese. Examples: "告訴" not "告诉", "個" not "个", "過" not "过", "為" not "为", "說" not "说", "這" not "这", "請" not "请", "麼" not "么", "後" not "后", "時" not "时", "對" not "对", "會" not "会". English content within the transcript stays in English.
```

Apply the same expansion to `AIPrompts.assistantMode` (line 42 in the same file):

Replace:
```swift
    If your response contains Chinese, it MUST use Traditional Chinese (Taiwan / zh-TW), NEVER Simplified Chinese. Examples: "告訴" not "告诉", "個" not "个", "過" not "过", "為" not "为", "說" not "说", "這" not "这". English content stays in English.
```

With:
```swift
    If your response contains Chinese, it MUST use Traditional Chinese (Taiwan / zh-TW), NEVER Simplified Chinese. Examples: "告訴" not "告诉", "個" not "个", "過" not "过", "為" not "为", "說" not "说", "這" not "这", "請" not "请", "麼" not "么", "後" not "后", "時" not "时", "對" not "对", "會" not "会". English content stays in English.
```

- [ ] **Step 3: Build to verify**

Run:
```bash
make local
```
Expected: build success.

---

### Task 5: Manual smoke test for Commit 1

**Files:** none

- [ ] **Step 1: Relaunch with new build**

Run:
```bash
make dev
```
Expected: app quits and relaunches; new build shows in `/Applications/VoiceInk.app`.

- [ ] **Step 2: Verify Default prompt now behaves as Verbatim**

In the running app: select the **Default** prompt (the only mode this commit touches). Record this sample utterance into a text editor (e.g., TextEdit):

> 「嗯，我我想說，這個 feature 啊，應該要支援 markdown 跟 plain text 兩種輸出。對對對就這樣。」

Expected output: substantially identical except for `嗯` and the `我我` stutter being collapsed:

> 「我想說，這個 feature 應該要支援 markdown 跟 plain text 兩種輸出。對對對就這樣。」

Counter-example (if you see this, the prompt is not taking effect): output is squashed to "這個 feature 應該支援 markdown 和 plain text。"

- [ ] **Step 3: If smoke test passes, proceed to commit**

If it doesn't pass: do NOT commit. Re-examine PromptTemplates.swift / AIPrompts.swift, check that the file changes are saved, that `make dev` actually rebuilt, and that you selected the Default prompt in the recorder UI.

---

### Task 6: Commit 1

**Files:**
- Stage: `VoiceInk/Models/PromptTemplates.swift`, `VoiceInk/Models/AIPrompts.swift`

- [ ] **Step 1: Stage files explicitly**

Run:
```bash
git add VoiceInk/Models/PromptTemplates.swift VoiceInk/Models/AIPrompts.swift
```

- [ ] **Step 2: Verify stage**

Run:
```bash
git status
```
Expected: only those two files staged.

- [ ] **Step 3: Commit**

Run:
```bash
git commit -m "$(cat <<'EOF'
feat(OPA-120): rewrite prompt rules (Verbatim + Summary) + wrapper examples

System Default template body → Verbatim rules (preserve every sentence, only drop
pure fillers + self-correction commands). New Summary template added (≥80%
sentence retention, local-reorder allowed but no high-level restructure).
Wrapper few-shot examples rewritten to remove sentence-dropping demos and
add 1 Chinese demo; CRITICAL LANGUAGE RULE example char list expanded 6→12 pairs.

This commit alone changes the behavior of Cmd+1 (Default → behaves as Verbatim).
Slot reordering and the new Summary slot land in commit 2.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## COMMIT 2 — 10-slot list + migration

### Task 7: Rebuild `PredefinedPrompts.createDefaultPrompts()`

**Files:**
- Modify: `VoiceInk/Models/PredefinedPrompts.swift` (full file rewrite)

- [ ] **Step 1: Replace the file content**

Open `VoiceInk/Models/PredefinedPrompts.swift`. Replace the entire file content with:

```swift
import Foundation
import SwiftUI

enum PredefinedPrompts {
    private static let predefinedPromptsKey = "PredefinedPrompts"

    // Static UUIDs for predefined prompts.
    // Verbatim REUSES the original Default UUID so existing user state (selectedPromptId
    // pointing to "Default", triggerWords, isActive) carries over with no data loss.
    // Assistant keeps its original UUID but moves from slot index 1 to slot index 9
    // (handled by the reorder step in AIEnhancementService.initializePredefinedPrompts).
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

    // Backwards-compat alias — old code paths may reference `defaultPromptId`.
    // Verbatim IS the new Default (it reuses the same UUID).
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
                promptText: verbatimText,  // clone Verbatim rules — safe fallback if user hits the hotkey
                icon: "questionmark.circle",
                description: "Unassigned hotkey slot. Currently behaves like Verbatim. Edit this prompt to assign a custom mode.",
                isPredefined: true,
                useSystemInstructions: true
            )
        }

        return [
            // Slot 0 → Cmd+1
            CustomPrompt(
                id: verbatimPromptId,
                title: "Verbatim",
                promptText: verbatimText,
                icon: "checkmark.seal.fill",
                description: "Preserve every sentence; only drop pure fillers and self-correction commands.",
                isPredefined: true,
                useSystemInstructions: true
            ),
            // Slot 1 → Cmd+2
            CustomPrompt(
                id: summaryPromptId,
                title: "Summary",
                promptText: summaryText,
                icon: "doc.text",
                description: "Light cleanup, ≥80% sentence retention. Local reorder allowed.",
                isPredefined: true,
                useSystemInstructions: true
            ),
            // Slots 2-8 → Cmd+3-9 (dummies)
            makeDummy(id: dummySlot3Id, slotNumber: 3),
            makeDummy(id: dummySlot4Id, slotNumber: 4),
            makeDummy(id: dummySlot5Id, slotNumber: 5),
            makeDummy(id: dummySlot6Id, slotNumber: 6),
            makeDummy(id: dummySlot7Id, slotNumber: 7),
            makeDummy(id: dummySlot8Id, slotNumber: 8),
            makeDummy(id: dummySlot9Id, slotNumber: 9),
            // Slot 9 → Cmd+0
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
```

- [ ] **Step 2: If `doc.text` or `questionmark.circle` PromptIcon cases don't exist, substitute**

Run:
```bash
grep -n "case " VoiceInk/Models/CustomPrompt.swift | head -30
```

If `doc.text` or `questionmark.circle` aren't valid `PromptIcon` cases, edit the file to use existing cases (e.g., for Summary use the same as existing predefined; for dummies pick any neutral case). The exact icon doesn't affect behavior.

- [ ] **Step 3: Build to verify**

Run:
```bash
make local
```
Expected: build success.

---

### Task 8: Rewrite `initializePredefinedPrompts()` with upsert+reorder

**Files:**
- Modify: `VoiceInk/Services/AIEnhancement/AIEnhancementService.swift:660-682` (existing `initializePredefinedPrompts` method)

- [ ] **Step 1: Replace the method body**

Open `VoiceInk/Services/AIEnhancement/AIEnhancementService.swift`. Find the `private func initializePredefinedPrompts()` method at line 660. Replace the entire method body (lines 660-682) with:

```swift
    /// Upsert predefined prompts by UUID (preserving user state like triggerWords/isActive),
    /// then reorder so predefined prompts appear in source order, with user-created prompts
    /// appended after. Idempotent: safe to run on every launch.
    private func initializePredefinedPrompts() {
        let predefinedTemplates = PredefinedPrompts.createDefaultPrompts()
        let predefinedUUIDs = Set(predefinedTemplates.map { $0.id })

        // Build the upserted predefined dict (preserving user state like triggerWords)
        var upserted: [UUID: CustomPrompt] = [:]
        for template in predefinedTemplates {
            if let existing = customPrompts.first(where: { $0.id == template.id }) {
                upserted[template.id] = CustomPrompt(
                    id: existing.id,
                    title: template.title,
                    promptText: template.promptText,
                    isActive: existing.isActive,
                    icon: template.icon,
                    description: template.description,
                    isPredefined: true,
                    triggerWords: existing.triggerWords,
                    useSystemInstructions: template.useSystemInstructions
                )
            } else {
                upserted[template.id] = template
            }
        }

        // Rebuild: predefined in source order, then user-created (preserving their order).
        let orderedPredefined = predefinedTemplates.compactMap { upserted[$0.id] }
        let userCreated = customPrompts.filter { !predefinedUUIDs.contains($0.id) }
        customPrompts = orderedPredefined + userCreated
    }
```

- [ ] **Step 2: Build to verify**

Run:
```bash
make local
```
Expected: build success.

---

### Task 9: Manual smoke test for Commit 2 (migration)

**Files:** none

- [ ] **Step 1: Pre-state snapshot**

Before launching the new build, capture the current customPrompts UserDefault state:
```bash
defaults read com.prakashjoshipax.VoiceInk customPrompts 2>/dev/null | head -50
```
Expected: JSON-ish dump showing 2 prompts (Default + Assistant) with their UUIDs `0001` and `0002`. Note the current `selectedPromptId`:
```bash
defaults read com.prakashjoshipax.VoiceInk selectedPromptId
```
Expected: usually `00000000-0000-0000-0000-000000000001` (Default).

- [ ] **Step 2: Relaunch**

Run:
```bash
make dev
```
Expected: app quits + relaunches.

- [ ] **Step 3: Verify post-migration state**

In the app, open Settings → AI Models → Prompts. You should see **10 prompts** in this exact order:
1. Verbatim
2. Summary
3. Slot 3 (Unassigned)
4. Slot 4 (Unassigned)
5. Slot 5 (Unassigned)
6. Slot 6 (Unassigned)
7. Slot 7 (Unassigned)
8. Slot 8 (Unassigned)
9. Slot 9 (Unassigned)
10. Assistant

Check via terminal:
```bash
defaults read com.prakashjoshipax.VoiceInk customPrompts 2>/dev/null | grep -E "title|^\s+\""
```
Expected: titles appear in the order Verbatim → Summary → Slot 3 ... Slot 9 → Assistant.

- [ ] **Step 4: Verify selectedPromptId still resolves**

If pre-state was `0001` (Default), it should now resolve to **Verbatim** (same UUID). The recorder UI should show "Verbatim" as the active prompt. Don't restart the test if the auto-selection is different — that's a migration concern, log it and investigate.

- [ ] **Step 5: Verify hotkey mapping**

Open mini-recorder. Press `Cmd+1` — Verbatim should be selected (notification feedback or visible selection change). Press `Cmd+2` — Summary should be selected. Press `Cmd+0` — Assistant should be selected. Press `Cmd+5` — Slot 5 (Unassigned) should be selected.

- [ ] **Step 6: Verify Summary mode behavior**

Record this utterance with Summary mode (Cmd+2):

> 「我今天在想啊，我們的 Privacy HUD 那個元件，現在 short recording 在 2 秒以內釋放的時候，OCR 還沒回來，但是因為我們在 success path 沒有檢查 race，所以舊的 OCR 回來之後又把 payload 寫回去了。這個 bug 在 long recording 不會發生。我覺得可以用 activeRecordingStartID 來解。明天試試看。」

Expected output: ≥80% sentence retention; opener "我今天在想啊" + thinking-aloud collapsed; all 4+ distinct propositions preserved (Privacy HUD bug existence, condition for triggering, why long recording is immune, proposed fix, plan for tomorrow). Output length ~70-90% of input.

Counter-example: if output is condensed to 3-4 bullet points or under 50% length — Summary rules aren't taking effect.

- [ ] **Step 7: Verify Assistant mode still works**

Record with Cmd+0: "現在幾點？" (or whatever the current time is). Expected: LLM responds with the current time (uses `<SYSTEM_CONTEXT>` injection from OPA-113). If it transcribes the question instead, Assistant mode is broken.

- [ ] **Step 8: If all smoke tests pass, proceed to commit**

---

### Task 10: Commit 2

**Files:**
- Stage: `VoiceInk/Models/PredefinedPrompts.swift`, `VoiceInk/Services/AIEnhancement/AIEnhancementService.swift`

- [ ] **Step 1: Stage files explicitly**

Run:
```bash
git add VoiceInk/Models/PredefinedPrompts.swift VoiceInk/Services/AIEnhancement/AIEnhancementService.swift
```

- [ ] **Step 2: Commit**

Run:
```bash
git commit -m "$(cat <<'EOF'
feat(OPA-120): 10-slot prompt layout + upsert-then-reorder migration

PredefinedPrompts rewritten to seed 10 slots: Verbatim (Cmd+1, reuses old
Default UUID), Summary (Cmd+2), Slot 3-9 (Cmd+3-9 dummies cloning Verbatim
rules), Assistant (Cmd+0, keeps old UUID but moves to slot index 9).

initializePredefinedPrompts() now upserts by UUID (preserving user
triggerWords/isActive) then reorders predefined prompts to match source
order, with user-created prompts appended after. Idempotent on every launch.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## COMMIT 3 — OpenCC dependency + converter + Settings toggle

### Task 11: Add SwiftyOpenCC SwiftPM dependency

**Files:**
- Modify: `VoiceInk.xcodeproj/project.pbxproj` (Xcode UI does this)
- Modify: `Package.resolved` (auto-generated)

- [ ] **Step 1: Add package via Xcode UI**

Open Xcode:
```bash
open VoiceInk.xcodeproj
```

In Xcode:
1. File → Add Package Dependencies...
2. Enter URL: `https://github.com/ddddxxx/SwiftyOpenCC`
3. Dependency rule: **Up to Next Major Version** from the latest tagged release. (Per CLAUDE.md supply chain rule — use a tagged release, not branch. As of writing latest is `1.x.y`; verify the exact tag in the GitHub releases tab before confirming.)
4. Add to target: **VoiceInk** (the main app target)
5. Product: `OpenCC`
6. Click "Add Package"

Xcode will resolve, download, and update `Package.resolved`.

- [ ] **Step 2: Verify tagged release pinned**

Run:
```bash
cat Package.resolved | grep -A 4 "SwiftyOpenCC"
```
Expected: a block showing `"version": "1.x.y"` (the tag you selected), and a `revision` field with the commit hash.

If the block shows `"branch": "main"` instead of `"version"`, the dependency is pinned to a branch — go back to Xcode and change the dependency rule to a specific version.

- [ ] **Step 3: Confirm import works**

Create a temporary test in `VoiceInk/AppDelegate.swift` (or any existing Swift file) — add at top:
```swift
import OpenCC
```

Run:
```bash
make local
```
Expected: build success, no "no such module 'OpenCC'" error.

Remove the temporary import line once build passes.

- [ ] **Step 4: Verify the API signatures**

Run:
```bash
find ~/Library/Developer/Xcode/DerivedData -name "OpenCC.swiftmodule" -path "*VoiceInk*" 2>/dev/null | head -1
```

Inspect SwiftyOpenCC's actual API by browsing its README at https://github.com/ddddxxx/SwiftyOpenCC, or:
```bash
find ~/Library/Developer/Xcode/DerivedData -name "ChineseConverter.swift" 2>/dev/null
```

Confirm the options syntax for s2twp profile. Expected (from SwiftyOpenCC README): `ChineseConverter.Options` is an `OptionSet`; for s2twp use `[.simplifiedToTraditional, .twPhrases]`. If the API differs in the version pinned, adjust Task 12 accordingly.

---

### Task 12: Create `TraditionalChineseConverter.swift`

**Files:**
- Create: `VoiceInk/Services/PostProcess/TraditionalChineseConverter.swift`

- [ ] **Step 1: Create the directory**

Run:
```bash
mkdir -p VoiceInk/Services/PostProcess
```

- [ ] **Step 2: Write the file**

Create `VoiceInk/Services/PostProcess/TraditionalChineseConverter.swift` with this content:

```swift
import Foundation
import OpenCC

/// Converts simplified Chinese characters to Traditional Chinese (Taiwan) using
/// OpenCC's s2twp profile. English / non-CJK content passes through untouched.
///
/// Layer is the deterministic safety net beneath the prompt-level
/// `[CRITICAL LANGUAGE RULE]` — the LLM may still emit simplified characters
/// (especially on short utterances; see OPA-117 spike), but this converter
/// catches them before the text reaches clipboard / history / paste.
///
/// Gated by the `useTraditionalChineseConversion` UserDefault (default true).
/// On init failure (dictionary missing, etc.), `convert(_:)` is a no-op —
/// fail open rather than break the paste pipeline.
@MainActor
final class TraditionalChineseConverter {
    static let shared = TraditionalChineseConverter()

    private let converter: ChineseConverter?

    private init() {
        do {
            self.converter = try ChineseConverter(options: [.simplifiedToTraditional, .twPhrases])
        } catch {
            self.converter = nil
        }
    }

    /// Returns the input unchanged if the conversion is disabled or the
    /// converter failed to initialize. Otherwise returns simplified→traditional
    /// (Taiwan, with phrase substitution e.g., 软件 → 軟體).
    func convert(_ text: String) -> String {
        guard UserDefaults.standard.bool(forKey: "useTraditionalChineseConversion") else {
            return text
        }
        guard let converter else { return text }
        return converter.convert(text)
    }
}
```

- [ ] **Step 3: Add the file to the Xcode target**

In Xcode (open `VoiceInk.xcodeproj` if not already), right-click `VoiceInk/Services/` → New Group from Folder → select `PostProcess/`. Verify `TraditionalChineseConverter.swift` is checked under "Add to Targets: VoiceInk".

Alternative: Xcode may auto-detect the file if Project Navigator is configured for folder-based references. Confirm via:
```bash
grep "TraditionalChineseConverter.swift" VoiceInk.xcodeproj/project.pbxproj
```
Expected: a few hits (one for `PBXFileReference`, one for `PBXSourcesBuildPhase`).

- [ ] **Step 4: Build to verify**

Run:
```bash
make local
```
Expected: build success.

---

### Task 13: Register UserDefault default value

**Files:**
- Modify: `VoiceInk/AppDefaults.swift:5-57`

- [ ] **Step 1: Add the registration entry**

Open `VoiceInk/AppDefaults.swift`. In the dictionary inside `registerDefaults()`, after the existing Clipboard group (after `"simulateTypingInsteadOfPaste": false,` on line 14), add a new group:

Before:
```swift
            // Clipboard
            "restoreClipboardAfterPaste": true,
            "clipboardRestoreDelay": 2.0,
            "useAppleScriptPaste": false,
            "simulateTypingInsteadOfPaste": false,

            // Audio & Media
```

After:
```swift
            // Clipboard
            "restoreClipboardAfterPaste": true,
            "clipboardRestoreDelay": 2.0,
            "useAppleScriptPaste": false,
            "simulateTypingInsteadOfPaste": false,

            // Output post-processing
            "useTraditionalChineseConversion": true,

            // Audio & Media
```

- [ ] **Step 2: Build to verify**

Run:
```bash
make local
```
Expected: build success.

---

### Task 14: Hook OpenCC into TranscriptionPipeline

**Files:**
- Modify: `VoiceInk/Transcription/Engine/TranscriptionPipeline.swift` (three insertion points)

- [ ] **Step 1: Insert conversion call after raw transcript**

Find line 119:
```swift
            transcription.text = cleanedText
```

Replace with:
```swift
            let convertedText = TraditionalChineseConverter.shared.convert(cleanedText)
            transcription.text = convertedText
```

And update line 123:
```swift
            finalPastedText = cleanedText
```
to:
```swift
            finalPastedText = convertedText
```

Why: when enhancement is OFF or skipped, this `cleanedText` IS what gets pasted + stored in history. Convert once, propagate.

- [ ] **Step 2: Insert conversion call after enhancement**

Find line 146-147 (inside the `do { ... }` block after enhancement runs):
```swift
                    let (enhancedText, enhancementDuration, promptName) = try await enhancementService.enhance(textForAI)
                    transcription.enhancedText = enhancedText
```

Replace with:
```swift
                    let (enhancedText, enhancementDuration, promptName) = try await enhancementService.enhance(textForAI)
                    let convertedEnhanced = TraditionalChineseConverter.shared.convert(enhancedText)
                    transcription.enhancedText = convertedEnhanced
```

And update line 153:
```swift
                    finalPastedText = enhancedText
```
to:
```swift
                    finalPastedText = convertedEnhanced
```

- [ ] **Step 3: Verify the import isn't needed**

`TraditionalChineseConverter` is in the same module (`VoiceInk` target), so no `import` statement is needed in `TranscriptionPipeline.swift`. Confirm by build.

- [ ] **Step 4: Build to verify**

Run:
```bash
make local
```
Expected: build success.

---

### Task 15: Add Settings toggle UI

**Files:**
- Modify: `VoiceInk/Views/Settings/SettingsView.swift` (two insertions: `@AppStorage` declaration + Toggle row)

- [ ] **Step 1: Add the `@AppStorage` declaration**

Find line 24:
```swift
    @AppStorage("simulateTypingInsteadOfPaste") private var simulateTypingInsteadOfPaste = false
```

Add directly after it:
```swift
    @AppStorage("useTraditionalChineseConversion") private var useTraditionalChineseConversion = true
```

- [ ] **Step 2: Add the Toggle in the Recording Feedback section**

Find the closing `}` of the `Recording Feedback` `Section` block. Currently it ends after the "Simulate Typing Instead of Paste" Toggle (line 212-213):

```swift
                Toggle(isOn: $simulateTypingInsteadOfPaste) {
                    HStack(spacing: 4) {
                        Text("Simulate Typing Instead of Paste")
                        InfoTip("Types each character as a simulated key event instead of pasting. Slower for long text, but avoids paste-collapse in apps like Claude Code CLI. Bypasses IME via direct Unicode injection. Note: Auto Send is disabled in this mode — press Enter manually after reviewing.")
                    }
                }
            }
```

Insert a new Toggle row **inside the section, after Simulate Typing**:

```swift
                Toggle(isOn: $simulateTypingInsteadOfPaste) {
                    HStack(spacing: 4) {
                        Text("Simulate Typing Instead of Paste")
                        InfoTip("Types each character as a simulated key event instead of pasting. Slower for long text, but avoids paste-collapse in apps like Claude Code CLI. Bypasses IME via direct Unicode injection. Note: Auto Send is disabled in this mode — press Enter manually after reviewing.")
                    }
                }

                // Traditional Chinese conversion
                Toggle(isOn: $useTraditionalChineseConversion) {
                    HStack(spacing: 4) {
                        Text("Convert Simplified Chinese to Traditional (Taiwan)")
                        InfoTip("Runs OpenCC s2twp on the final transcript before paste/history. Catches simplified characters that the LLM language rule sometimes misses on short utterances. English content is unchanged. Toggle off if you want to preserve simplified Chinese input verbatim (e.g., quoting a mainland source).")
                    }
                }
            }
```

- [ ] **Step 3: Build to verify**

Run:
```bash
make local
```
Expected: build success.

---

### Task 16: Manual smoke test for Commit 3 (OpenCC)

**Files:** none

- [ ] **Step 1: Relaunch**

Run:
```bash
make dev
```

- [ ] **Step 2: Verify Settings toggle is visible and defaults ON**

In the app, Settings → Recording Feedback section. Confirm "Convert Simplified Chinese to Traditional (Taiwan)" toggle is present and turned ON.

- [ ] **Step 3: Smoke test conversion ON path**

With Verbatim selected (Cmd+1), dictate a sentence designed to produce simplified output (or compose one that the LLM might emit as simplified). Suggested test phrases:

a. Pure simplified-leaning short sentence: 「跑完告訴我三個都過嗎」
   Expected output: contains 「告訴」 not 「告诉」, 「個」 not 「个」, 「過」 not 「过」.

b. Mainland-flavored tech vocabulary (Whisper may produce simplified): "讓我打開软件設定". After OpenCC + s2twp profile: should be "讓我打開軟體設定" (simplified char converted + 软件→軟體 phrase substitution).

c. Mixed English + Chinese: "let me check the 设定 first". After: "let me check the 設定 first" (English untouched, Chinese converted).

- [ ] **Step 4: Smoke test conversion OFF path**

Toggle OFF the conversion. Dictate the same test phrase from (a). Expected: output passes through unchanged from whatever the LLM produces. If the LLM happened to output traditional already, this is a no-op test — try toggling enhancement off and dictating a phrase you know Whisper will produce as simplified, then verify it stays simplified.

- [ ] **Step 5: Smoke test history consistency**

Open the History window. Verify that the entries from steps 3-4 show the same text as what was pasted (history entry should be already-converted when toggle is ON).

- [ ] **Step 6: Smoke test no-conversion edge cases**

Pure English: "let me check the API response format". After: unchanged.
Pure traditional Chinese: "請打開軟體設定看一下". After: unchanged (idempotent — s2twp on already-traditional input produces same output).

- [ ] **Step 7: If all smoke tests pass, proceed to commit**

---

### Task 17: Commit 3

**Files:**
- Stage: `VoiceInk.xcodeproj/project.pbxproj`, `Package.resolved`, `VoiceInk/Services/PostProcess/TraditionalChineseConverter.swift`, `VoiceInk/AppDefaults.swift`, `VoiceInk/Transcription/Engine/TranscriptionPipeline.swift`, `VoiceInk/Views/Settings/SettingsView.swift`

- [ ] **Step 1: Stage all files explicitly**

Run:
```bash
git add VoiceInk.xcodeproj/project.pbxproj Package.resolved VoiceInk/Services/PostProcess/TraditionalChineseConverter.swift VoiceInk/AppDefaults.swift VoiceInk/Transcription/Engine/TranscriptionPipeline.swift VoiceInk/Views/Settings/SettingsView.swift
```

- [ ] **Step 2: Verify stage**

Run:
```bash
git status
```
Expected: only the six files staged.

- [ ] **Step 3: Commit**

Run:
```bash
git commit -m "$(cat <<'EOF'
feat(OPA-120): OpenCC s2twp post-process for simplified→traditional Chinese

Adds SwiftyOpenCC SwiftPM dependency (pinned tagged release, MIT, no network).
New TraditionalChineseConverter singleton (lazy init, fail-open on dict missing,
gated by useTraditionalChineseConversion UserDefault default ON).

Three hook calls in TranscriptionPipeline: on cleanedText (raw transcript path),
on enhancedText (enhanced path), so both history and paste receive the converted
text. Settings toggle in Recording Feedback section.

Deterministic safety net beneath the prompt-level CRITICAL LANGUAGE RULE.
Catches the short-utterance leak documented in OPA-117 that LLM self-discipline
can't fully close.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## OPTIONAL COMMIT 4 — CLAUDE.md log entry + supply chain + watch list

Land this commit ONLY after Tasks 5/9/16 smoke tests all pass and the branch survives ≥1 day of real daily-driver usage. The log records what's verified to work.

### Task 18: Append to CLAUDE.md

**Files:**
- Modify: `CLAUDE.md` (append-only log + supply chain section + watch list)

- [ ] **Step 1: Append OPA-120 log entry**

Open `CLAUDE.md`. Find the end of the `## Append-only log` section (the very bottom of the file). Append a new bullet matching the existing pattern:

```markdown
- **2026-05-26**: OPA-120 — 三模式 prompt 系統（Verbatim Cmd+1 / Summary Cmd+2 / Assistant Cmd+0）+ OpenCC s2twp post-process。Predefined prompts 從 2 個改成 10 個（Verbatim、Summary、Slot 3-9 dummies、Assistant），既有 Default UUID 被 reuse 為 Verbatim、Assistant UUID 不動但 index 從 1 搬到 9。`initializePredefinedPrompts()` 改成 upsert-by-UUID + reorder-to-source-order，preserve user 的 triggerWords / isActive / 既有 customPrompts。Prompt 規則重寫：Verbatim 嚴格保留每句話（只刪 嗯/呃/喔/啊 + stutters + 自我修正命令）；Summary ≥80% sentence retention（local reorder 允許、high-level restructure 禁止）。Wrapper few-shot examples 重寫（移除誤導性的「丟整句」示範、加 1 個中文 example）+ `[CRITICAL LANGUAGE RULE]` 例字 6→12 對。新增 SwiftyOpenCC SwiftPM dependency（pin tagged release）+ `Services/PostProcess/TraditionalChineseConverter.swift`，hook 在 `TranscriptionPipeline` 末端覆蓋 raw transcript + enhanced text + final paste，確保 history 與 paste 一致。新增 Settings → Recording Feedback → "Convert Simplified Chinese to Traditional (Taiwan)" toggle, default ON。改動：`Models/PromptTemplates.swift`、`Models/AIPrompts.swift`、`Models/PredefinedPrompts.swift`、`Services/AIEnhancement/AIEnhancementService.swift`、`AppDefaults.swift`、`Services/PostProcess/TraditionalChineseConverter.swift`（新）、`Transcription/Engine/TranscriptionPipeline.swift`、`Views/Settings/SettingsView.swift`、`VoiceInk.xcodeproj`、`Package.resolved`。Spec: `docs/superpowers/specs/2026-05-26-three-mode-prompts-design.md`. Plan: `docs/superpowers/plans/2026-05-26-three-mode-prompts.md`. 3 implementation commits on branch `feat/three-mode-prompts`.
```

- [ ] **Step 2: Add SwiftyOpenCC to the Supply chain section**

Find the `### Supply chain caveat` section (around line 130-138). Below the existing paragraph about LLMkit / mediaremote-adapter, add a new entry:

```markdown

**Added dependencies (audited)**:

- `SwiftyOpenCC` (ddddxxx/SwiftyOpenCC) — MIT, pinned to tagged release `<version-here>` in `Package.resolved`. Audited 2026-05-26. Provides OpenCC s2twp simplified→traditional Chinese conversion. Pure Swift wrapper over OpenCC's bundled dictionaries; no network.
```

Replace `<version-here>` with the actual tag pinned in Task 11 Step 2.

- [ ] **Step 3: Update the watch list**

Find the `### Critical files to watch on upstream pulls` section. Add `TranscriptionPipeline.swift` to the list (or add a note that the OpenCC conversion hook lives there):

```markdown
- `VoiceInk/Transcription/Engine/TranscriptionPipeline.swift` (OpenCC hook points around lines 119, 146, 153) — any upstream rewrite of the pipeline assembly needs to preserve the three conversion calls.
```

- [ ] **Step 4: Commit**

Run:
```bash
git add CLAUDE.md
git commit -m "$(cat <<'EOF'
docs(OPA-120): log three-mode prompts + OpenCC landing

Append-only log entry recording what landed on branch feat/three-mode-prompts.
Supply chain section adds SwiftyOpenCC audit note. Watch list adds
TranscriptionPipeline OpenCC hook for upstream pull awareness.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Post-implementation: dog-food before merge to main

Per CLAUDE.md ≥3 days rule + this plan's recommendation ≥7 days (new dependency + behavior change). Use as daily-driver on `feat/three-mode-prompts` branch:

- [ ] Day 1-2: Verbatim with blog drafting (target: confirm sentences-preserved feel right)
- [ ] Day 3-4: Verbatim with Claude CC CLI (target: confirm typing-mode + Verbatim combo works for inline editing)
- [ ] Day 5-6: Summary mode for IM / short notes (target: 80% retention feels right)
- [ ] Day 7: Re-verify migration if you `defaults delete` and let it rebuild from scratch

If issues found:
- Prompt rule misbehavior: open a follow-up commit on the same branch to tweak the rule text
- OpenCC over/under conversion: same — adjust the converter or add an option
- Migration data loss: revert commit 2, investigate before re-attempting

Once stable, merge to main:
```bash
git checkout main
git merge --no-ff feat/three-mode-prompts
```

---

## Self-review checklist (writer ran this)

- **Spec coverage:**
  - §3.1 Verbatim rules → Task 2 ✓
  - §3.2 Summary rules → Task 3 ✓
  - §3.3 Assistant unchanged → preserved by reusing `AIPrompts.assistantMode` in Task 7 ✓
  - §3.4 Dummy slots → Task 7 `makeDummy()` helper ✓
  - §4.1 Wrapper few-shot rewrite → Task 4 Step 1 ✓
  - §4.2 CRITICAL LANGUAGE RULE 6→12 chars → Task 4 Step 2 (both customPromptTemplate + assistantMode) ✓
  - §5.1 10-slot list with explicit UUIDs → Task 7 ✓
  - §5.2 Migration upsert+reorder → Task 8 ✓
  - §5.3 Existing user state preserved → covered by Task 9 Step 1 pre-snapshot + Task 8 logic ✓
  - §6.1 Single hook point in pipeline → Task 14 (three hook calls, justified for history consistency) ✓
  - §6.2 SwiftyOpenCC + s2twp → Task 11 ✓
  - §6.3 Supply chain pinning → Task 11 Step 2 + Task 18 Step 2 ✓
  - §6.4 Converter API → Task 12 ✓
  - §6.5 Settings toggle default ON → Task 13 + Task 15 ✓
  - §7 phasing 3 commits → Tasks 6, 10, 17 ✓
  - §8 test plan → smoke tasks 5, 9, 16 ✓
  - §9 rollback per commit → addressed by clean commit boundaries ✓

- **Placeholder scan:** No TBD/TODO/`<placeholder>` in any task step. The one explicit `<version-here>` in Task 18 Step 2 is a runtime-determined value (the implementer must fill in the actual SwiftyOpenCC version they pinned in Task 11), with an inline note saying so — not a planning gap.

- **Type consistency:** `verbatimPromptId` / `summaryPromptId` / `assistantPromptId` / `dummySlot3Id`-`dummySlot9Id` used consistently across Task 7 and Task 8. `useTraditionalChineseConversion` UserDefault key consistent across Tasks 12, 13, 15. `TraditionalChineseConverter.shared.convert(_:)` signature stable across Tasks 12 and 14.
