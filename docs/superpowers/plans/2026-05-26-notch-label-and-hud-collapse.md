# Notch Mode Label + Privacy HUD Collapse Toggle — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Two independent UX polish items: (1) notch + mini recorder show the active prompt's title next to the icon (persistent label, not toast); (2) Privacy HUD gets a collapse toggle that shrinks it to a 30pt destination-colored pill, with state persisted via UserDefault.

**Architecture:** Two single-purpose commits in one PR. Commit 1 modifies the shared `RecorderPromptButton` to embed a truncated `Text` label after the icon — affects both notch and mini recorders. Commit 2 adds an `@AppStorage`-backed collapse state to `PrivacyHUDView`, conditional expanded vs. collapsed layouts, a minimize chevron overlay, and a NotificationCenter event that triggers the window manager to re-measure and reposition the NSPanel on toggle.

**Tech Stack:** Swift / SwiftUI (`@AppStorage`, `Text` + `Image` HStack, `.overlay(alignment:)`) / AppKit (`NSHostingController.fittingSize` for panel resize) / NotificationCenter (single custom notification for cross-layer signal).

**Linear:** [OPA-121](https://linear.app/opass/issue/OPA-121)
**Spec:** `docs/superpowers/specs/2026-05-26-notch-label-and-hud-collapse-design.md`

**Branch:** `feat/notch-label-and-hud-collapse`

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `VoiceInk/Views/Recorder/RecorderComponents.swift` | Owns `RecorderPromptButton`, `RecorderPowerModeButton`, `RecorderToggleButton` | Wrap existing `RecorderToggleButton` invocation in an HStack with a `Text` label showing `enhancementService.activePrompt?.title ?? "Default"`, with `.lineLimit(1) + .truncationMode(.tail) + .frame(maxWidth: 110)` |
| `VoiceInk/AppDefaults.swift` | Centralized UserDefault registration | Add one entry: `"privacyHUDCollapsed": false` |
| `VoiceInk/Views/Recorder/PrivacyHUDView.swift` | Visual rendering of `PrivacyPayload` | Add `@AppStorage("privacyHUDCollapsed")` state, branch body between expanded (existing fields + new minimize button overlay) and collapsed (~30pt circular pill with destination-colored background), define `Notification.Name.privacyHUDCollapseDidChange`, post notification on toggle |
| `VoiceInk/Views/Recorder/PrivacyHUDWindowManager.swift` | Owns `PrivacyHUDPanel` lifecycle, observes payload changes | Subscribe to `.privacyHUDCollapseDidChange` via NotificationCenter, on event trigger `showOrUpdate(with: enhancementService.currentPrivacyPayload)` to re-measure + reposition the panel |

**Why this decomposition:**
- `RecorderPromptButton` is the single source of truth for the prompt indicator — modifying it once flips both notch and mini behavior atomically. No need to plumb a `showLabel` parameter through callsites.
- The HUD collapse state lives in `@AppStorage`, not in window-manager state, because the view is the natural owner. The window manager only needs to know "size changed, re-measure" — a single notification is the right contract.
- `Notification.Name.privacyHUDCollapseDidChange` is a one-shot signal, not state. No need for a singleton or store.

## Testing approach

**No unit tests.** Established codebase pattern (see OPA-115 / OPA-120 plans). SwiftUI view, AppKit panel sizing, UserDefaults, NotificationCenter — none of these have test infrastructure in this repo. Verification is `make local` + manual smoke per spec §6.

## Convention notes for the implementer

- **`make local`** builds to `/Applications/VoiceInk.app` via Personal Team signing. Requires `.local-team` file (gitignored) with Team ID — owner has this set up.
- **`make dev` = `make local && make relaunch`** — preferred for daily iteration. Quits the running app and relaunches the fresh build. Use this only when the controller (me) hands off to the user for smoke testing. Do NOT run `make dev` from the implementer subagent.
- **Don't run `git add` / `git commit` / `git push`** from the implementer — the controller handles commits after spec/code review and user smoke test.
- **Commit messages**: project pattern is short imperative lowercase with optional scope prefix. Examples: `feat(OPA-121): notch + mini show active prompt title next to icon`, `feat(OPA-121): Privacy HUD collapse toggle with destination-color pill`.
- **No emojis** in code, in commits, or in user-facing copy (other than what's already in the Privacy HUD field icons — those are existing).
- **No comments** unless explaining a non-obvious "why" (codebase convention). Especially: don't narrate what the code does.
- **`PromptIcon` is `typealias PromptIcon = String`** (SF Symbol name), so anywhere icon: takes a literal string SF Symbol name.
- **The harness shows SourceKit "Cannot find type X / No such module Y" warnings** after file edits — these are LSP indexer staleness, not real compile errors. The `make local` build succeeded each time this pattern appeared throughout OPA-120. Don't flag these.

---

## COMMIT 1 — Notch + Mini mode label

### Task 1: Create branch

**Files:** none (workspace state)

- [ ] **Step 1: Verify clean working tree on main**

Run:
```bash
git status
git branch --show-current
```
Expected: clean tree, on `main`. (Spec was just committed at HEAD = `5f11620`.)

- [ ] **Step 2: Create branch**

Run:
```bash
git checkout -b feat/notch-label-and-hud-collapse
```
Expected: `Switched to a new branch 'feat/notch-label-and-hud-collapse'`

---

### Task 2: Add label next to icon in `RecorderPromptButton`

**Files:**
- Modify: `VoiceInk/Views/Recorder/RecorderComponents.swift:161-187` (`RecorderPromptButton.body`)

- [ ] **Step 1: Replace the body**

Open `/Users/opass/Workspace/VoiceTwInk/VoiceInk/Views/Recorder/RecorderComponents.swift`. Find `RecorderPromptButton.body` (lines 161-187). It currently looks like:

```swift
    var body: some View {
        RecorderToggleButton(
            isEnabled: enhancementService.isEnhancementEnabled,
            icon: enhancementService.activePrompt?.icon ?? enhancementService.allPrompts.first(where: { $0.id == PredefinedPrompts.defaultPromptId })?.icon ?? "checkmark.seal.fill",
            disabled: false
        ) {
            if enhancementService.isEnhancementEnabled {
                activePopover = activePopover == .enhancement ? .none : .enhancement
            } else {
                enhancementService.isEnhancementEnabled = true
            }
        }
        .frame(width: buttonSize)
        .padding(padding)
        .onHover {
            isHoveringButton = $0
            syncPopoverVisibility()
        }
        .popover(isPresented: .constant(activePopover == .enhancement), arrowEdge: .bottom) {
            EnhancementPromptPopover()
                .environmentObject(enhancementService)
                .onHover {
                    isHoveringPopover = $0
                    syncPopoverVisibility()
                }
        }
    }
```

Replace with:

```swift
    var body: some View {
        HStack(spacing: 6) {
            RecorderToggleButton(
                isEnabled: enhancementService.isEnhancementEnabled,
                icon: enhancementService.activePrompt?.icon ?? enhancementService.allPrompts.first(where: { $0.id == PredefinedPrompts.defaultPromptId })?.icon ?? "checkmark.seal.fill",
                disabled: false
            ) {
                if enhancementService.isEnhancementEnabled {
                    activePopover = activePopover == .enhancement ? .none : .enhancement
                } else {
                    enhancementService.isEnhancementEnabled = true
                }
            }
            .frame(width: buttonSize)

            Text(activePromptTitle)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 110, alignment: .leading)
        }
        .padding(padding)
        .onHover {
            isHoveringButton = $0
            syncPopoverVisibility()
        }
        .popover(isPresented: .constant(activePopover == .enhancement), arrowEdge: .bottom) {
            EnhancementPromptPopover()
                .environmentObject(enhancementService)
                .onHover {
                    isHoveringPopover = $0
                    syncPopoverVisibility()
                }
        }
    }

    private var activePromptTitle: String {
        if let active = enhancementService.activePrompt {
            return active.title
        }
        if let fallback = enhancementService.allPrompts.first(where: { $0.id == PredefinedPrompts.defaultPromptId }) {
            return fallback.title
        }
        return "Default"
    }
```

Changes:
- Wraps the existing `RecorderToggleButton(...)` chain in an `HStack(spacing: 6)`.
- Adds a `Text(activePromptTitle)` after the button with size constraints to prevent layout overflow.
- The `.frame(width: buttonSize)` stays on the button itself; `.padding(padding)` and the `.onHover` / `.popover` modifiers move to the outer `HStack` so hover region covers icon + label together.
- New `activePromptTitle` computed property follows the same fallback chain as the existing icon expression.

**Foreground color rationale:** The notch background is `Color.black` (per `NotchRecorderView.swift:108`), so `.white.opacity(0.85)` matches the existing notch text aesthetic. Mini recorder uses a translucent dark background; the same color reads OK there too.

- [ ] **Step 2: Build verify**

Run:
```bash
make local
```
Expected: clean build, no errors. Artifacts at `/Applications/VoiceInk.app`.

---

### Task 3: STOP — hand off for spec review + code review + user smoke

The implementer subagent's work ends here. The controller (me) handles:
- Spec compliance reviewer subagent
- Code quality reviewer subagent
- User runs `make dev` and verifies smoke spec §6.1
- After user passes smoke, controller commits Commit 1

---

### Task 4 (controller): Commit 1

**Files:** stage two-file diff explicitly.

- [ ] **Step 1: Stage**

```bash
git add VoiceInk/Views/Recorder/RecorderComponents.swift
```

- [ ] **Step 2: Verify stage**

```bash
git status
```
Expected: only `RecorderComponents.swift` staged.

- [ ] **Step 3: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(OPA-121): notch + mini show active prompt title next to icon

RecorderPromptButton wraps the existing icon button in an HStack with a
truncated Text label showing enhancementService.activePrompt?.title. Both
notch and mini recorders inherit the change since they share this component.
Label caps at 110pt with tail truncation so long titles like
"Slot 5 (Unassigned)" don't break notch layout.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## COMMIT 2 — Privacy HUD collapse toggle

### Task 5: Register UserDefault

**Files:**
- Modify: `VoiceInk/AppDefaults.swift` (add one entry alongside the "Output post-processing" group added in OPA-120)

- [ ] **Step 1: Add the entry**

Find the section added for OPA-120 (currently around lines 16-18):

```swift
            // Output post-processing
            "useTraditionalChineseConversion": true,

            // Audio & Media
```

Insert a new entry between these so the file still groups logically:

Before:
```swift
            // Output post-processing
            "useTraditionalChineseConversion": true,

            // Audio & Media
```

After:
```swift
            // Output post-processing
            "useTraditionalChineseConversion": true,

            // Privacy HUD UI state
            "privacyHUDCollapsed": false,

            // Audio & Media
```

- [ ] **Step 2: Build verify**

```bash
make local
```
Expected: clean build.

---

### Task 6: Add notification name + collapse logic to `PrivacyHUDView`

**Files:**
- Modify: `VoiceInk/Views/Recorder/PrivacyHUDView.swift` (full body rewrite — current file is 124 lines, new file ~155 lines)

- [ ] **Step 1: Replace the entire file**

Open `/Users/opass/Workspace/VoiceTwInk/VoiceInk/Views/Recorder/PrivacyHUDView.swift`. Replace its full content with:

```swift
import SwiftUI

extension Notification.Name {
    /// Posted when the user toggles the Privacy HUD collapsed state.
    /// PrivacyHUDWindowManager observes this to re-measure and reposition the panel.
    static let privacyHUDCollapseDidChange = Notification.Name("PrivacyHUDCollapseDidChange")
}

/// Visual rendering of the PrivacyPayload. Pure presentation — no business logic.
/// Each ContextField is rendered as a single row; .disabled and .empty cases are
/// not rendered at all so the HUD shrinks naturally when fields are absent.
///
/// Branches between expanded (full content) and collapsed (small destination-colored
/// pill) based on @AppStorage `privacyHUDCollapsed`. State persists across launches.
struct PrivacyHUDView: View {
    let payload: PrivacyPayload

    @AppStorage("privacyHUDCollapsed") private var isCollapsed: Bool = false

    var body: some View {
        if isCollapsed {
            collapsedPill
        } else {
            expandedPanel
        }
    }

    // MARK: - Collapsed pill

    private var collapsedPill: some View {
        Button(action: toggleCollapsed) {
            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.black.opacity(0.65))
                .frame(width: 30, height: 30)
                .background(backgroundColor)
                .clipShape(Circle())
                .shadow(radius: 4)
        }
        .buttonStyle(.plain)
        .help("Expand Privacy HUD")
    }

    // MARK: - Expanded panel

    private var expandedPanel: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 6) {
                renderField(name: "Selected", icon: "✂️", field: payload.selectedText) { text in
                    text
                }
                renderField(name: "Clipboard", icon: "📋", field: payload.clipboard) { text in
                    text
                }
                renderField(name: "Screen", icon: "🖥", field: payload.screenContext) { val in
                    let prefix = val.appName.isEmpty ? "" : "[\(val.appName)] "
                    return prefix + val.extractedText
                }
                renderField(name: "Vocab", icon: "📚", field: payload.customVocabulary) { text in
                    text
                }
                renderField(name: "Time", icon: "🕐", field: payload.systemContext) { val in
                    "\(val.dayOfWeek) \(formatTime(val.timestamp)) (\(val.timezone))"
                }

                Divider().opacity(0.4)
                destinationFooter
            }
            .padding(10)
        }
        .background(backgroundColor)
        .cornerRadius(10)
        .shadow(radius: 4)
        .frame(maxWidth: 700)
        .overlay(alignment: .topTrailing) {
            Button(action: toggleCollapsed) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.black.opacity(0.55))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(4)
            .help("Collapse Privacy HUD")
        }
    }

    // MARK: - Toggle

    private func toggleCollapsed() {
        isCollapsed.toggle()
        NotificationCenter.default.post(name: .privacyHUDCollapseDidChange, object: nil)
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
            EmptyView()
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
            HStack(alignment: .top, spacing: 6) {
                Text(icon).font(.system(size: 12))
                Text(name).font(.system(size: 11, weight: .semibold))
                Text(valueFormatter(value))
                    .font(.system(size: 11, design: .monospaced))
                    .opacity(0.8)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
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

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private func formatTime(_ d: Date) -> String {
        Self.timeFormatter.string(from: d)
    }
}
```

Key changes from the original file:
- Added `extension Notification.Name { static let privacyHUDCollapseDidChange = ... }` at the top.
- Added `@AppStorage("privacyHUDCollapsed") private var isCollapsed`.
- Top-level `body` now branches `if isCollapsed { collapsedPill } else { expandedPanel }`.
- New `collapsedPill` view: 30pt circular `Button` showing `chevron.down`, bg = `backgroundColor` (destination-colored), tap calls `toggleCollapsed()`.
- The existing `body` content was renamed to `expandedPanel` and gained an `.overlay(alignment: .topTrailing) { ... chevron.up button ... }` for the minimize action.
- New `toggleCollapsed()` flips `isCollapsed` (triggers UserDefault write via `@AppStorage`) and posts `.privacyHUDCollapseDidChange` so the window manager can re-measure.

- [ ] **Step 2: Build verify**

```bash
make local
```
Expected: clean build.

---

### Task 7: Wire up `PrivacyHUDWindowManager` to observe the notification

**Files:**
- Modify: `VoiceInk/Views/Recorder/PrivacyHUDWindowManager.swift` (add NotificationCenter subscription in `observePayload()` and a new method)

- [ ] **Step 1: Add notification observer**

Open `/Users/opass/Workspace/VoiceTwInk/VoiceInk/Views/Recorder/PrivacyHUDWindowManager.swift`. Find the `observePayload()` method (line 19-31) and extend it.

Replace:
```swift
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
```

With:
```swift
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

        NotificationCenter.default.publisher(for: .privacyHUDCollapseDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleCollapseToggle()
            }
            .store(in: &cancellables)
    }

    /// Re-measure and reposition the panel when the user toggles collapsed state.
    /// The payload itself doesn't change — only the view's intrinsic content size.
    private func handleCollapseToggle() {
        guard let payload = enhancementService.currentPrivacyPayload else { return }
        showOrUpdate(with: payload)
    }
```

Changes:
- Subscribe to `.privacyHUDCollapseDidChange` notifications via Combine's `NotificationCenter.publisher`.
- On notification, call new private `handleCollapseToggle()` which re-invokes `showOrUpdate(with: currentPayload)`.
- `showOrUpdate` already re-measures via `measuredSize(host:)` and repositions via `PrivacyHUDPositioner.calculateFrame` — reusing the same path is the cleanest fit.

- [ ] **Step 2: Build verify**

```bash
make local
```
Expected: clean build.

---

### Task 8: STOP — hand off for spec review + code review + user smoke

The implementer subagent's work ends here. Controller dispatches reviewers and hands off to user for smoke testing per spec §6.2.

---

### Task 9 (controller): Commit 2

**Files:** stage the three-file diff explicitly.

- [ ] **Step 1: Stage**

```bash
git add VoiceInk/AppDefaults.swift VoiceInk/Views/Recorder/PrivacyHUDView.swift VoiceInk/Views/Recorder/PrivacyHUDWindowManager.swift
```

- [ ] **Step 2: Verify stage**

```bash
git status
```
Expected: only those three files staged.

- [ ] **Step 3: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(OPA-121): Privacy HUD collapse toggle with destination-color pill

Adds @AppStorage-backed privacyHUDCollapsed state to PrivacyHUDView. When
collapsed, the HUD shrinks to a 30pt circular pill whose background color
preserves the destination signal (green=local, yellow=cloud) — privacy
visual anchor remains, just minimized. Toggle is a chevron-up overlay in
expanded mode and the whole pill is tappable in collapsed mode.

State persists across launches via UserDefault. Window manager subscribes
to a new .privacyHUDCollapseDidChange notification and re-measures the
NSPanel via the existing showOrUpdate path so the panel resizes cleanly.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Post-implementation

No dog-food window required (spec §5: pure visual, no new deps, no privacy behavior change). After both commits pass smoke, merge to main and create a v0.2.0 GitHub release.

Suggested merge command after both commits land:

```bash
git checkout main
git merge --no-ff feat/notch-label-and-hud-collapse -m "$(cat <<'EOF'
Merge branch 'feat/notch-label-and-hud-collapse' — OPA-121 notch label + HUD collapse

Lands persistent prompt-title label in notch/mini RecorderPromptButton and
a Privacy HUD collapse toggle that shrinks the HUD to a destination-colored
pill, with state persisted via UserDefault.

Spec: docs/superpowers/specs/2026-05-26-notch-label-and-hud-collapse-design.md
Plan: docs/superpowers/plans/2026-05-26-notch-label-and-hud-collapse.md
Linear: https://linear.app/opass/issue/OPA-121
EOF
)"
git push origin main
git tag -a v0.2.0 -m "v0.2.0 — notch label + Privacy HUD collapse"
git push origin v0.2.0
gh release create v0.2.0 --repo opass/VoiceTwInk --title "v0.2.0 — Notch mode label + Privacy HUD collapse" --notes "..."
```

(Controller will draft the release notes when the time comes — not part of the implementer's scope.)

---

## Self-review checklist (writer ran this)

- **Spec coverage:**
  - §3.1 RecorderPromptButton modification → Task 2 ✓
  - §3.2 notch visual + §3.3 width constraint → Task 2 (maxWidth: 110, lineLimit, truncationMode) ✓
  - §3.4 unchanged parts (collapsed state, popover, hotkey) → Task 2 preserves all of these (`.popover` modifier and `syncPopoverVisibility` left intact) ✓
  - §4.1 UserDefault registration → Task 5 ✓
  - §4.1 expanded vs. collapsed branching → Task 6 (Body branches `if isCollapsed`) ✓
  - §4.2 visual mockup (chevron-up overlay topTrailing + 30pt circular pill) → Task 6 ✓
  - §4.3 destination color preserved in collapsed pill → Task 6 (`.background(backgroundColor)` on Button) ✓
  - §4.4 click sources (chevron-up button + tap-the-pill) → Task 6 (`Button(action: toggleCollapsed)` in both paths) ✓
  - §4.5 NotificationCenter resize mechanism → Task 6 (post side) + Task 7 (observe side + handleCollapseToggle) ✓
  - §4.6 unchanged parts (capture-at-record-start, ESC, system context, activeRecordingStartID) → Tasks 5-7 don't touch any of those paths ✓
  - §5 phasing 2 commits → Tasks 4 (Commit 1) + Task 9 (Commit 2) ✓
  - §6.1 / §6.2 / §6.3 smoke plans → controller hands off after Task 3 and Task 8 ✓
  - §7 per-commit rollback → addressed by independent file scopes in Commits 1 and 2 ✓

- **Placeholder scan:** No TBD / TODO / "implement later" / unspecified handlers anywhere in the plan. The release notes template marker at the very end (`--notes "..."`) is explicitly tagged as the controller's later work, not part of any implementer step.

- **Type consistency:** `activePromptTitle` defined once in Task 2 and only referenced inside the same struct. `isCollapsed`, `toggleCollapsed()`, `collapsedPill`, `expandedPanel`, `.privacyHUDCollapseDidChange`, `handleCollapseToggle()` all defined in Task 6 / 7 and referenced consistently. `backgroundColor` (existing computed property in PrivacyHUDView) is reused unchanged in `collapsedPill` — same name, same return type.
