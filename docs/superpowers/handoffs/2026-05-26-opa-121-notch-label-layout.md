# OPA-121 Notch Label Layout — Handoff to Codex

**Date**: 2026-05-26
**From**: Claude (controller agent)
**To**: Codex
**Repo**: `/Users/opass/Workspace/VoiceTwInk`
**Branch**: `feat/notch-label-and-hud-collapse` (dirty — see "Working tree state" below)
**Linear**: [OPA-121](https://linear.app/opass/issue/OPA-121)
**Spec**: `docs/superpowers/specs/2026-05-26-notch-label-and-hud-collapse-design.md`
**Plan**: `docs/superpowers/plans/2026-05-26-notch-label-and-hud-collapse.md`

---

## TL;DR

Implementing **Commit 1 of OPA-121** (persistent prompt-title label in notch + mini RecorderPromptButton). Label IS rendering, but **the notch's left side is being covered by the Privacy HUD overlay**, AND/OR the notch's `pillWidth` is exceeding what the macOS notch can visually accommodate so part of the label extends outside the clipped/visible notch area. User can see only `"ot 4 (Unassi…"` instead of `"[icon] Slot 4 (Unassi…"` — the icon + first 2 chars of label are hidden.

Need: figure out the actual root cause and fix it so the full label is visible in both notch and mini modes without obstructing or being obstructed by other UI elements (especially the Privacy HUD which appears immediately below the notch via `PrivacyHUDPositioner`).

Commit 2 (Privacy HUD collapse toggle) is NOT YET STARTED — don't touch that yet.

---

## Working tree state at handoff

```
$ git status --short
 M VoiceInk/Views/Recorder/MiniRecorderView.swift
 M VoiceInk/Views/Recorder/NotchRecorderView.swift
 M VoiceInk/Views/Recorder/RecorderComponents.swift

$ git log --oneline -3
6bb67bc docs(OPA-121): notch mode label + Privacy HUD collapse — implementation plan
5f11620 docs(OPA-121): notch mode label + Privacy HUD collapse — design spec
ec053e5 Merge branch 'feat/three-mode-prompts' — OPA-120 three-mode prompts + OpenCC
```

Three files modified but uncommitted. The implementer subagent + I made edits — both spec-compliance reviewer and code-quality reviewer ALREADY APPROVED the changes (no Important findings). Smoke test by the user revealed the visual bug.

If you need to start clean: `git restore VoiceInk/Views/Recorder/{MiniRecorderView,NotchRecorderView,RecorderComponents}.swift` reverts to the spec-and-plan state from main HEAD.

---

## What was implemented (the spec-approved change)

### Change 1 — `VoiceInk/Views/Recorder/RecorderComponents.swift` (lines ~145-215)

`RecorderPromptButton.body` rewrote from a single icon button to an `HStack(spacing: 6)` containing the icon button + a `Text` label:

```swift
var body: some View {
    HStack(spacing: 6) {
        RecorderToggleButton(
            isEnabled: enhancementService.isEnhancementEnabled,
            icon: activePromptIcon,
            disabled: false
        ) { /* tap handler unchanged */ }
        .frame(width: buttonSize)

        Text(activePromptTitle)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.white.opacity(0.85))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: 110, alignment: .leading)
    }
    .padding(padding)
    .onHover { /* unchanged */ }
    .popover(...) { /* unchanged */ }
}

private var activePromptTitle: String {
    enhancementService.activePrompt?.title
        ?? enhancementService.allPrompts.first { $0.id == PredefinedPrompts.defaultPromptId }?.title
        ?? "Default"
}

private var activePromptIcon: PromptIcon {
    enhancementService.activePrompt?.icon
        ?? enhancementService.allPrompts.first { $0.id == PredefinedPrompts.defaultPromptId }?.icon
        ?? "checkmark.seal.fill"
}
```

Important details:
- The `.padding`, `.onHover`, `.popover` modifiers moved from being applied to the inner button to being applied to the outer HStack. Hover/popover region intentionally covers both icon + label.
- `RecorderPromptButton` is shared by `NotchRecorderView` AND `MiniRecorderView`. Single source of truth.

### Change 2 — `VoiceInk/Views/Recorder/NotchRecorderView.swift` line 51-52

Expanded the notch's side expansion constants because the label needed more space:

```swift
// BEFORE (spec/main):
private let recordingSideExpansion: CGFloat = 90
private let transcriptSideExpansion: CGFloat = 110

// AFTER (my fix attempt):
private let recordingSideExpansion: CGFloat = 170
private let transcriptSideExpansion: CGFloat = 190
```

Rationale: The original 90pt budget had to fit prompt button (icon + label) + power mode button + outer padding + HStack spacing. With label adding up to 110pt, content overflowed and label rendered with 0 width (invisible). Bumped expansion to give layout room.

### Change 3 — `VoiceInk/Views/Recorder/MiniRecorderView.swift` line 15-16

Same problem in mini recorder. Bumped the bar width:

```swift
// BEFORE:
private let compactWidth: CGFloat = 184
private let expandedWidth: CGFloat = 300

// AFTER:
private let compactWidth: CGFloat = 280
private let expandedWidth: CGFloat = 360
```

---

## Observed bug after the fix attempt

**Reported by user with screenshot**: The notch shows partial text `"ot 4 (Unassi…"` — the leading icon and the `"Sl"` prefix of the label `"Slot 4 (Unassigned)"` are hidden. PowerMode icon (✨) appears at far right of the visible black notch area. The Privacy HUD (yellow card with Clipboard + Screen fields) overlay sits in the lower portion of the screen but its position is suspiciously close to / possibly overlapping the leading edge of the notch.

User has the recorder running with active prompt = "Slot 4 (Unassigned)". Recording is active (Privacy HUD is showing).

## Hypotheses, ranked

### H1 — Privacy HUD overlapping the notch's leading edge (medium-high likelihood)

The notch is now `pillWidth = notchWidth + recordingSideExpansion * 2 = ~180 + 340 = ~520pt` wide when active. On many MacBooks the menu-bar-area outside the physical notch is wide enough, but the **PrivacyHUDPositioner places the HUD at `screenFrame.midX - (hudSize.width / 2)`** which is screen-centered, and the HUD width can be up to 700pt. The HUD is also positioned to appear immediately below the notch:

```swift
// VoiceInk/Views/Recorder/PrivacyHUDPositioner.swift
case .notch:
    let notchHeight: CGFloat = 36
    let yPosition = screenFrame.maxY - notchHeight - padding - hudSize.height
    return NSRect(x: centerX, y: yPosition, width: hudSize.width, height: hudSize.height)
```

So the HUD is screen-centered horizontally, positioned right below the notch vertically. If the notch's pill expands beyond what the OS treats as "menubar area" or if the HUD's Y position is wrong, the HUD's top edge could clip into the notch's bottom area, hiding the leading portion of the notch widget.

**Inspect**: Does the HUD's y-position need adjustment for the new pillHeight (notch widget got taller too if pillHeight changed)? Is the HUD rendering ABOVE the notch panel z-order-wise?

### H2 — Layout container still under-budget despite the expansion (medium likelihood)

Even with `recordingSideExpansion = 170pt`, the HStack containing prompt button + power mode button + spacer is in a `.frame(width: 170)` container. Compute the actual budget:

```
HStack {
    RecorderPromptButton  // icon(20) + spacing(6) + label(maxWidth 110) = 136pt intrinsic
    RecorderPowerModeButton  // ~20pt
    Spacer(minLength: 0)
}
.padding(.leading, 14)
.frame(width: 170)
```

- Leading padding: 14pt
- Available: 170 - 14 = 156pt
- HStack spacing between children: 10pt (looking at NotchRecorderView line 123)
- Prompt button intrinsic: 20 + 6 + 110 = 136pt
- Power mode button: ~20pt
- Required: 136 + 10 + 20 = 166pt → **10pt over budget**

SwiftUI compresses excess. The Text view with `.lineLimit(1) + .truncationMode(.tail)` compresses by truncating from the tail. But the user is seeing the LEADING side cut off ("ot 4" instead of "Slot 4"), which is INCONSISTENT with tail truncation. So this hypothesis alone doesn't explain the observed glyph-cut.

**However**: if the icon is being clipped first (because the HStack content gets pushed left by the constraint failure), the visible window starts from somewhere INSIDE the prompt button, exposing only the latter portion of the label. This could explain "ot 4 (Unassi…" — the label is intact but the **viewport** into it is shifted right.

**Inspect**: Does increasing `recordingSideExpansion` further (e.g., to 220pt) make the bug go away? If yes, this is the cause. If no, look at H1 or H3.

### H3 — NotchShape clipping the leading edge (low-medium likelihood)

The pill's `.clipShape(NotchShape(...))` clips content to the notch's curved shape. If `NotchShape` is implemented to assume specific geometric proportions (typical notch curvature), expanding `pillWidth` by 80pt per side might cause the shape to clip content that's outside its expected curve area.

**Inspect**: `NotchShape` — find this file (likely in `Views/Recorder/` or somewhere nearby). Does the shape's path depend on input frame proportions in a way that breaks at larger pillWidths?

```bash
find /Users/opass/Workspace/VoiceTwInk/VoiceInk -name "NotchShape*"
```

### H4 — Some panel-level width constraint capping the actual visible area (low likelihood but worth checking)

`NotchWindowManager.swift` configures the `NotchRecorderPanel`. If the panel itself has a hard width constraint that doesn't track `pillWidth`, the SwiftUI view believes it has 520pt to render but the OS-level panel only exposes a smaller area.

**Inspect**: `VoiceInk/Views/Recorder/NotchWindowManager.swift` and `NotchRecorderPanel.swift`. Look for any width-related panel configuration.

---

## Reproduction steps

1. Make sure you're on branch `feat/notch-label-and-hud-collapse` and the three files are dirty (or restore them, then re-apply the changes documented above).
2. Build + relaunch: `make local && make relaunch` (or `make dev` which is the combined target).
3. Open the app. Settings → Interface → Recorder Style → confirm "Notch" is selected (you can also test "Mini" — same class of issue likely).
4. Hit the recording hotkey. Notch widget appears with prompt button + label.
5. Press `Cmd+4` to select "Slot 4 (Unassigned)". Observe the label truncation behavior.
6. If Privacy HUD appears (enhancement is on + has captured context), observe whether it's overlapping the notch.

Owner is daily-driving this fork, so any test you do is also being audit-watched. **Do not commit, push, merge, or run destructive git ops without explicit user approval.** Just diagnose + write code + ask user to verify.

---

## What to verify when you think you've fixed it

Spec §6.1 smoke checklist:
- Start a recording. Notch shows `[icon] Verbatim` (default).
- Press `Cmd+2` → label flips to "Summary".
- Press `Cmd+0` → "Assistant".
- Press `Cmd+5` → "Slot 5 (Unas…" (truncated with tail ellipsis).
- Switch Settings → Interface → Recorder Style → **Mini** → repeat checks.
- Disable enhancement → button still renders, label says "Default" (fallback path).
- During recording with enhancement on, Privacy HUD appears and does NOT overlap or hide the notch's prompt button area.

Build verification: `make local` succeeds (don't run `make dev` until you're ready to test interactively).

---

## Constraints you must honor

From `/Users/opass/Workspace/VoiceTwInk/CLAUDE.md`:
- **Privacy is the bar**: anything touching Privacy HUD behavior needs owner approval. Your scope is purely layout/visibility — don't change `assemblePrivacyPayload` or related paths.
- **Build only via `make local`** — don't `brew install`, don't install upstream commercial binary.
- **No emojis in code or commits**.
- **No comments unless explaining non-obvious "why"**.
- **No unit tests in this codebase** — verification is `make local` + manual smoke.
- **Don't auto-commit anything** — let the human review your fix before any `git add` / `git commit`.
- **Don't run `make dev`** if not necessary — it relaunches the running app, which interrupts whatever the user is doing.
- **Upstream divergence is a cost** — minimize change footprint to just what's needed for this bug.

If your fix changes layout constants beyond what's already in the dirty diff, it'll be a new visual decision the user wants to weigh in on. Surface the proposed change (e.g., "I want to bump `recordingSideExpansion` from 170 to 220") for confirmation before applying.

---

## What I tried that didn't work

1. **First attempt**: implemented label per the plan with `.frame(maxWidth: 110)` only — label rendered with 0 width because the parent HStack container in `NotchRecorderView` was hard-constrained to 90pt and couldn't fit both buttons + label.
2. **Second attempt** (current state): bumped `recordingSideExpansion` 90→170 and `compactWidth` 184→280. Label now renders, but the user reports `"ot 4 (Unassi…"` indicating either the icon + leading prefix are clipped, or the HUD is covering them.

## What I'd try next (if I were Codex)

Verify in this order:
1. **Confirm the bug isn't just Privacy HUD overlap**: ask the user to disable AI Enhancement (or pause Privacy HUD if there's a way), record again, screenshot the notch alone. If label is fine without HUD, the bug is HUD positioning (H1) — fix `PrivacyHUDPositioner.calculateFrame(mode: .notch, ...)` Y-position calculation, possibly accounting for the new wider notch widget.
2. **If label IS still clipped without HUD**: read `NotchShape.swift` to verify it scales correctly with the wider pillWidth (H3). Or further bump `recordingSideExpansion` (H2) and re-verify.
3. **If neither**: read `NotchWindowManager.swift` for panel-level constraints (H4).

Don't change the spec's intent (persistent label, white 0.85 opacity, 11pt medium, maxWidth 110). The spec is approved. The bug is in the visual rendering, not the spec text.

---

## Files you'll touch (likely)

- `VoiceInk/Views/Recorder/PrivacyHUDPositioner.swift` (if H1)
- `VoiceInk/Views/Recorder/NotchRecorderView.swift` (if H2 — further bump expansion)
- `VoiceInk/Views/Recorder/NotchShape.swift` (if H3 — shape definition)
- `VoiceInk/Views/Recorder/NotchWindowManager.swift` (if H4 — panel constraint)

Don't touch `RecorderComponents.swift` unless you have a strong reason — the `RecorderPromptButton` change passed both spec compliance and code quality review.

## When done

- Don't commit. Surface your diagnosis + proposed fix to the user, get their approval, and stop. The user (Opass) will run smoke test and decide whether to commit + move on to Commit 2 (Privacy HUD collapse toggle, separate scope).
- If your fix requires changing the SPEC (e.g., dropping persistent label in favor of toast-on-switch because the layout fundamentally can't accommodate), escalate that decision to the user — don't unilaterally change the design.

Good luck.
