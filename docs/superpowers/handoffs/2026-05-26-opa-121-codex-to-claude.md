# OPA-121 Notch Label + Privacy HUD Collapse — Handoff from Codex to Claude Code

**Date**: 2026-05-26
**From**: Codex
**To**: Claude Code
**Repo**: `/Users/opass/Workspace/VoiceTwInk`
**Branch**: `feat/notch-label-and-hud-collapse`
**Status**: implementation done, uncommitted, needs owner smoke test
**Related handoff**: `docs/superpowers/handoffs/2026-05-26-opa-121-notch-label-layout.md`
**Spec**: `docs/superpowers/specs/2026-05-26-notch-label-and-hud-collapse-design.md`
**Plan**: `docs/superpowers/plans/2026-05-26-notch-label-and-hud-collapse.md`

---

## TL;DR

Codex fixed both requested issues:

1. **Notch label clipped on the left**: root cause was not the Privacy HUD. `NotchRecorderView` had been expanded to `transcriptSideExpansion = 190`, but the containing `NotchRecorderPanel.calculateWindowMetrics()` still hard-coded `maxSideExpansion = 110`. SwiftUI rendered a wider pill than the NSPanel frame, so the panel clipped the left/right edges. Fixed by changing panel `maxSideExpansion` to `190`.
2. **Privacy HUD missing collapse toggle**: implemented `@AppStorage("privacyHUDCollapsed")` collapse state, a chevron-up control in expanded mode, a 30pt destination-colored pill in collapsed mode, and a NotificationCenter bridge so the AppKit panel re-measures/repositions after toggle.

No commit was made. No privacy payload assembly/send path was touched.

---

## Current Working Tree

Expected `git status --short` after Codex work:

```text
 M VoiceInk/AppDefaults.swift
 M VoiceInk/Views/Recorder/MiniRecorderView.swift
 M VoiceInk/Views/Recorder/NotchRecorderPanel.swift
 M VoiceInk/Views/Recorder/NotchRecorderView.swift
 M VoiceInk/Views/Recorder/PrivacyHUDView.swift
 M VoiceInk/Views/Recorder/PrivacyHUDWindowManager.swift
 M VoiceInk/Views/Recorder/RecorderComponents.swift
?? docs/superpowers/handoffs/
```

Notes:

- `MiniRecorderView.swift`, `NotchRecorderView.swift`, and `RecorderComponents.swift` were already dirty from the previous implementation attempt described in the prior handoff.
- Codex added changes to `AppDefaults.swift`, `NotchRecorderPanel.swift`, `PrivacyHUDView.swift`, and `PrivacyHUDWindowManager.swift`.
- This handoff file itself is newly untracked under `docs/superpowers/handoffs/`.

---

## Fix 1: Notch Label Clipping

### Root Cause

`NotchRecorderView` currently computes the active/live pill width from these constants:

```swift
private let recordingSideExpansion: CGFloat = 170
private let transcriptSideExpansion: CGFloat = 190
```

But `NotchRecorderPanel.calculateWindowMetrics()` still had:

```swift
let maxSideExpansion: CGFloat = 110
```

That meant the SwiftUI view believed it could draw up to:

```text
notchWidth + 190 * 2
```

while the AppKit panel only exposed:

```text
notchWidth + (110 + sideMargin) * 2
```

The visible symptom, `"ot 4 (Unassi…"` instead of `"Slot 4 (Unassi…"`, is consistent with NSPanel-level clipping of the left side of the wider SwiftUI pill.

### Change

File: `VoiceInk/Views/Recorder/NotchRecorderPanel.swift`

```diff
-        let maxSideExpansion: CGFloat = 110
+        let maxSideExpansion: CGFloat = 190
```

This keeps the AppKit panel envelope aligned with the largest SwiftUI notch state (`transcriptSideExpansion`).

---

## Fix 2: Privacy HUD Collapse Toggle

### UserDefault

File: `VoiceInk/AppDefaults.swift`

Added:

```swift
// Privacy HUD UI state
"privacyHUDCollapsed": false,
```

### View UI

File: `VoiceInk/Views/Recorder/PrivacyHUDView.swift`

Added:

- `Notification.Name.privacyHUDCollapseDidChange`
- `@AppStorage("privacyHUDCollapsed") private var isCollapsed`
- body branch between `collapsedPill` and `expandedPanel`
- expanded mode chevron-up button in top-right overlay
- collapsed mode 30pt circular pill with `backgroundColor`
- `toggleCollapsed()` that flips `@AppStorage` and posts the notification on next main-queue turn

Important implementation detail:

```swift
private func toggleCollapsed() {
    isCollapsed.toggle()
    DispatchQueue.main.async {
        NotificationCenter.default.post(name: .privacyHUDCollapseDidChange, object: nil)
    }
}
```

The async post ensures `@AppStorage` has propagated before the window manager reads `UserDefaults.standard.bool(forKey:)`.

### Panel Resize / Reposition

File: `VoiceInk/Views/Recorder/PrivacyHUDWindowManager.swift`

Added a Combine subscription:

```swift
NotificationCenter.default.publisher(for: .privacyHUDCollapseDidChange)
    .receive(on: DispatchQueue.main)
    .sink { [weak self] _ in
        self?.handleCollapseToggle()
    }
    .store(in: &cancellables)
```

Added `handleCollapseToggle()`:

```swift
private func handleCollapseToggle() {
    guard let payload = enhancementService.currentPrivacyPayload else { return }
    showOrUpdate(with: payload)
}
```

Updated existing-panel path to force layout before reading `fittingSize`:

```swift
hostingController.rootView = PrivacyHUDView(payload: payload)
hostingController.view.layoutSubtreeIfNeeded()
let size = measuredSize(host: hostingController)
```

Updated `measuredSize` so collapsed HUD actually shrinks instead of remaining a 700pt-wide invisible panel:

```swift
let isCollapsed = UserDefaults.standard.bool(forKey: "privacyHUDCollapsed")
let width = isCollapsed ? max(fitting.width, 30) : 700
let minHeight: CGFloat = isCollapsed ? 30 : 60
let height = min(max(fitting.height, minHeight), maxHeight)
return NSSize(width: width, height: height)
```

This is a deliberate improvement over the original implementation plan, which would have re-rendered a small SwiftUI pill inside a still-700pt NSPanel.

---

## Verification Already Run

### Passed

```bash
git diff --check
```

Passed with no whitespace errors.

```bash
xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug \
  -derivedDataPath .local-build \
  -clonedSourcePackagesDirPath .local-build/SourcePackages \
  CODE_SIGN_IDENTITY= CODE_SIGNING_ALLOWED=NO \
  build CLANG_MODULE_CACHE_PATH=.local-build/ModuleCache
```

Passed with:

```text
** BUILD SUCCEEDED **
```

### Could Not Run to Completion

```bash
make local
```

Failed before compiling due to local signing setup:

```text
Error: No 'Apple Development' cert found in keychain for team Z337ZVS3WT.
Open Xcode -> Settings -> Accounts, sign in, and let it create the cert.
```

This is environment/keychain state, not a compile failure. The no-sign xcodebuild compile passed.

---

## Manual Smoke Test Needed

Ask owner to run a signed local build once certificate setup is available, or run their normal local workflow.

### Notch Label

- Start recording in Notch mode.
- Confirm prompt button shows icon + full leading text, e.g. `Slot 4 (Unassi...)`, not `ot 4`.
- Press `Cmd+1`, `Cmd+2`, `Cmd+0`, `Cmd+5`.
- Confirm labels update and long titles tail-truncate, not left-clip.
- Confirm Privacy HUD appearing below the notch does not hide notch controls.

### Mini Label

- Switch recorder style to Mini.
- Repeat prompt shortcut checks.
- Confirm compact/expanded width still looks acceptable.

### Privacy HUD Collapse

- Start recording with enhancement/context active so HUD appears.
- Expanded HUD should show a chevron-up button at top-right.
- Click chevron-up: HUD should become a small 30pt destination-colored pill.
- Click pill: HUD should expand again.
- End recording and start again: collapsed/expanded state should persist.
- Quit and relaunch app: state should still persist.
- If destination changes local/cloud, collapsed pill color should follow the current payload destination.

---

## Review Notes / Risks

- The notch clipping fix is intentionally minimal: it only aligns AppKit panel width with existing SwiftUI expansion constants. No additional visual constants were invented.
- `PrivacyHUDView` still uses existing field icons and existing destination colors. No payload content or privacy semantics changed.
- `PrivacyHUDWindowManager.measuredSize()` still uses fixed `700` width for expanded mode to preserve current HUD layout.
- Collapsed mode width uses fitting size with a 30pt floor. If AppKit reports slightly larger intrinsic width because of button internals, that is acceptable; the visible pill remains 30pt.
- The added notification name lives in `PrivacyHUDView.swift`. If the team prefers central notification definitions, move it later, but this compiles and keeps scope small.
- There are existing build warnings unrelated to this work. Codex did not address them.

---

## Suggested Commit Split

If smoke passes, commit in two logical chunks:

### Commit 1: Notch + Mini Label

Files:

```text
VoiceInk/Views/Recorder/RecorderComponents.swift
VoiceInk/Views/Recorder/NotchRecorderView.swift
VoiceInk/Views/Recorder/NotchRecorderPanel.swift
VoiceInk/Views/Recorder/MiniRecorderView.swift
```

Suggested message:

```text
feat(OPA-121): show active prompt title in recorder controls
```

### Commit 2: Privacy HUD Collapse

Files:

```text
VoiceInk/AppDefaults.swift
VoiceInk/Views/Recorder/PrivacyHUDView.swift
VoiceInk/Views/Recorder/PrivacyHUDWindowManager.swift
```

Suggested message:

```text
feat(OPA-121): add Privacy HUD collapse toggle
```

Do not commit this handoff unless project convention wants handoff docs tracked.

