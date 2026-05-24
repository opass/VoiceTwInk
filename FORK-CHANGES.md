# Fork Changes

This document explains what VoiceTwInk adds beyond upstream [Beingpax/VoiceInk](https://github.com/Beingpax/VoiceInk), with motivation, technical approach, and known trade-offs for each improvement.

Each section corresponds to one of the five fork-specific improvements summarized in the [README](./README.md). For the deepest detail (commit SHAs, file:line references, fork decision log), see [CLAUDE.md](./CLAUDE.md). For the design specs of individual improvements, see [`docs/superpowers/specs/`](./docs/superpowers/specs/).

---

## 1. Privacy HUD

**What it does.** A floating SwiftUI panel appears alongside the recorder during dictation and shows every context field about to be sent to the LLM: selected text (via Accessibility), clipboard content, Screen OCR output (via Vision framework), custom vocabulary entries, and system context (time, timezone, locale). Each field has a visual indicator showing whether it has content and whether that content is empty, captured, pending, or omitted. The destination is colored green for local (Ollama / localhost) or yellow for cloud (any external LLM provider). Pressing ESC during recording cancels the entire pipeline — no transcription, no LLM call, no paste.

**Why it matters.** Upstream's AI Enhancement, once enabled with Accessibility permission, silently bundles whatever is currently selected on screen plus your clipboard into every LLM request. There is no UI to preview, audit, or opt out of these context fields per-utterance. For users dictating near sensitive data (passwords selected in a password manager, private messages, API keys in clipboard), this is a real information leak that the user has no visibility into. The HUD makes the leak visible and stoppable.

**Technical approach.** Context is captured at recording start (not at LLM-send time), so the displayed snapshot is exactly what will be sent. A new `PrivacyHUDWindowManager` observes a `@Published var currentPrivacyPayload` on `AIEnhancementService` via Combine. The panel mirrors the existing recorder positioning logic (above the MiniRecorder, below the Notch). Two new global toggles (`useSelectedTextContext`, `useCustomVocabularyContext`) close the previous silent-inclusion gap; both default to ON for backwards compatibility but can be turned off without disabling AI Enhancement entirely. The `getSystemMessage()` method reads captured properties first with on-demand fallback so HUD failures don't break the enhance pipeline.

**Known trade-offs.**
- The HUD adds UI surface area at record time. If too intrusive, the per-field toggles let you disable selected-text or vocabulary inclusion entirely.
- Capture-at-start means context that changes mid-recording isn't reflected — intentional, since predictability beats freshness here.
- Late context capture (e.g., slow Screen OCR completing after recording ended) is gated by the recording session ID so it can't re-publish a stale payload after the HUD has been cleared.

---

## 2. Traditional Chinese tuning

**What it does.** Two changes across two layers. At the Whisper transcription layer: a new "Chinese (Taiwan)" language option in Settings (internally tagged BCP-47 `zh-TW`, translated to `zh` at the API boundary because Whisper rejects region tags). When selected, a Taiwan-specific seed prompt is included in the Whisper API call to bias the model toward 繁體中文 and Taiwan vocabulary (`捷運` not `地铁`, `軟體` not `软件`, `滑鼠` not `鼠标`, etc.). At the LLM enhancement layer: the default system prompt now includes a top-priority `[CRITICAL LANGUAGE RULE - OVERRIDES ALL OTHERS]` block with explicit Traditional/Simplified character pairs as examples (告訴 not 告诉, 個 not 个, 過 not 过, 為 not 为, 說 not 说, 這 not 这), forcing the LLM to output Traditional Chinese.

**Why it matters.** Whisper's default Chinese output is Simplified, and cloud LLMs — especially on short inputs — often normalize Traditional Chinese back to Simplified. The fork is positioned for Taiwanese users, so getting Traditional Chinese output reliably across both layers is core to the value.

**Technical approach.**
- New language entry in `LanguageDictionary`; helper converts BCP-47 `zh-TW` to ISO `zh` before sending to Whisper.
- Seed prompt is a 4-sentence natural Taiwan paragraph that name-drops specific vocabulary markers (LINE, YouTube, 軟體, 滑鼠, 捷運, 健保) — these prime Whisper's token distribution toward Taiwan-flavored output.
- Enhancement layer change is in `AIPrompts.customPromptTemplate` and `AIPrompts.assistantMode`: a primacy-position language rule with English instruction (LLMs follow English instructions more reliably) plus Chinese character pair examples (essential for unambiguously specifying which forms are wanted).

**Known trade-offs.**
- The "Chinese (Taiwan)" Whisper seed prompt is aggressive enough to force **English audio into Chinese** — an unintended translation side-effect verified empirically with `curl` against the Groq Whisper API. Test setup: pure English audio "I think this application is very elegant" with `language=zh` and the zh-TW seed prompt → output 「我覺得這個應用程式很優雅。」 (translated). Same audio with auto-detect and no seed prompt → output "I think this application is very elegant." (preserved).
- **Therefore the recommended Settings is language = Auto-detect, not "Chinese (Taiwan)"** — auto-detect bypasses the Whisper-side seed prompt and relies entirely on the enhancement-layer rule to convert any Simplified output to Traditional.
- The auto-detect recommendation only works if AI Enhancement is enabled. With Enhancement off, auto-detect Chinese output will be Simplified (Whisper's default).
- A future improvement direction is per-Power-Mode language selection — letting you set "Chinese (Taiwan) with seed prompt" for Chinese-only text editors while keeping Auto-detect for mixed-language chat apps. Not yet implemented.

---

## 3. Build from source by default

**What it does.** `make local` builds and deploys the app to `/Applications/`. `make dev` rebuilds and relaunches a running VoiceInk. `make check` verifies the toolchain. The build is signed with a free Apple Developer Personal Team certificate (no $99/year account required).

**Why it matters.** Upstream's commercial model: source is fully open under GPL v3, but the licensed binary buys you automatic updates and support. For a privacy-focused user, the gap between "source is open" and "the binary I'm running is the same as the source I just read" is closed only by self-building. There's no programmatic way to verify a downloaded binary was built from the public source — you have to trust the maintainer's build pipeline. Self-building from a freshly cloned repo eliminates that trust requirement.

A secondary benefit: building with Apple Developer Personal Team certs (rather than ad-hoc) means macOS TCC's permission database tracks the app by a stable identity. Without this, every rebuild looks like a fresh app to macOS and you'd be re-granting Microphone and Accessibility permissions every time.

**Technical approach.**
- `LocalBuild.xcconfig` plus a `LOCAL_BUILD` Swift compilation flag distinguishes local-build behavior at compile time.
- `LicenseViewModel.swift` short-circuits the license check in `LOCAL_BUILD` mode — the build never calls `api.polar.sh`, even on first launch. Mac serial number and hostname never leave the machine via this app.
- Hybrid signing: build phase uses ad-hoc (because SPM dependencies' auto-generated build targets are unfriendly to Apple Development certs); after the build completes, the `Makefile` re-signs the wrapper `.app` with the Apple Development cert from the gitignored `.local-team` file. TCC only checks the wrapper's designated requirement, which stays stable across rebuilds.
- `KeychainService` falls back to UserDefaults under `LOCAL_BUILD` because Keychain requires stable code signing to persist data reliably across rebuilds.

**Known trade-offs.**
- No iCloud dictionary sync in local builds (Keychain disabled in `LOCAL_BUILD`).
- No automatic updates — pull `main` and rebuild manually.
- One-time setup requires Xcode, an Apple ID added under Xcode → Settings → Accounts, and writing your Team ID into a `.local-team` file at the repo root.

---

## 4. Simulate Typing Mode

**What it does.** A Settings toggle (`Simulate Typing Instead of Paste`, default off, in the Recording Feedback section). When enabled, the existing paste pipeline (clipboard write + Cmd+V simulation) is replaced with per-character keyboard event injection via `CGEventKeyboardSetUnicodeString`. The mode also has two paired behaviors: AutoSend is force-disabled (regardless of Power Mode settings) so the user reviews and presses Enter manually; and newlines in the LLM output are translated to Shift+Return injection, preserving paragraph structure without prematurely submitting in chat-style apps.

**Why it matters.** Claude Code CLI (the fork owner's primary voice-input target) auto-collapses any large paste into a `[Pasted text +N lines]` symbol, making inline review and editing impossible before submitting. Other chat-style inputs (Slack, Discord, ChatGPT web) have similar collapse behavior on long pastes. For multi-paragraph dictation, the upstream paste flow was a friction point worth solving.

**Technical approach.**
- A branch was added at the top of `CursorPaster.performPasteSession`: read the `simulateTypingInsteadOfPaste` UserDefault, route to a new `typeAtCursor()` if true.
- `typeAtCursor()` iterates `String.Character` (Swift's grapheme cluster type — correctly handles emoji and accented characters), converts each to UTF-16, and posts keyDown/keyUp `CGEvent` pairs with `keyboardSetUnicodeString` attached. A 5ms inter-character delay paces the injection so receiving apps don't drop keystrokes.
- `CGEventKeyboardSetUnicodeString` bypasses keyboard layout and IME translation — characters are inserted as Unicode directly, so 注音 (Bopomofo) input methods don't intercept them mid-sentence.
- AutoSend gate is one line in `TranscriptionPipeline.swift`: the existing `if let autoSendKey, autoSendKey.isEnabled` condition gains `&& !simulateTyping`.
- Newline handling: the typing loop detects `\n` and posts a Shift+Return `CGEvent` (virtualKey `0x24` + `.maskShift`) instead of unicode-injecting the raw `\n`. Shift+Enter is the standard "newline without submit" gesture across chat-style apps and behaves as a plain newline in GUI text editors — cross-app behavior is consistent.

**Known trade-offs.**
- Typing is slower than paste — about 5ms per character means ~2.5 seconds for a 500-character paragraph. Acceptable for review-friendly contexts; would be tedious for high-volume content.
- AutoSend (configurable per Power Mode upstream) is suppressed entirely in typing mode. There's no escape hatch — the semantic intent of "I want to review before send" overrides any AutoSend configuration.
- Some apps may interpret Shift+Return differently from a plain newline (e.g., certain vim-mode editors). Not encountered in normal use, but possible. If this becomes an issue, the fix would be per-app override or a Settings sub-option.

---

## 5. GPL v3, forever

**What it does.** Maintains upstream's GPL v3 licensing. All fork-specific changes remain open source. There are no proprietary code paths, no hidden telemetry, no closed-source dependencies whose behavior could change without your knowledge.

**Why it matters.** For a tool that records audio, has Accessibility access to selected text, captures screenshots via Vision, and can send arbitrary context to LLM providers — license-locked auditability is the difference between "I trust the maintainer not to add tracking" and "any tracking would have to be visible in the source code I can read". The GPL contagion clause ensures this property cannot regress in any redistribution.

**Technical approach.** No code change — GPL v3 inherited from upstream's [LICENSE](./LICENSE). The fork's working agreement is that PRs introducing GPL-incompatible code or dependencies will be declined.

**Known limitations.**
- GPL is contagious — anyone who redistributes this code (modified or not) must also distribute their source. For most personal users this is irrelevant; for any business considering integration, it's load-bearing.
- The license cannot be changed to anything more permissive — that would require relicensing upstream's contributions, which is practically impossible.
- Two SwiftPM dependencies are forks owned by the upstream maintainer pinned to `branch: main` (LLMkit, mediaremote-adapter). Every `swift package update` pulls the latest commit from these forks. Supply chain note: it's on the fork's roadmap to pin to specific audited commit hashes.

---

## See also

- [README](./README.md) — high-level overview of the fork's positioning
- [CLAUDE.md](./CLAUDE.md) — full project context, privacy audit, append-only decision log
- [BUILDING.md](./BUILDING.md) — first-time build setup
