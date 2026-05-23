# VoiceTwInk

A fork of [VoiceInk](https://github.com/Beingpax/VoiceInk) with a Taiwanese twist — maintained as a personal daily-driver voice input tool for macOS, with Traditional Chinese workflow tuning and an explicit privacy posture.

> Voice input I trust, that I can keep adjusting to fit how I actually work.

This file is the project's always-on context for any AI assistant working here. It is the **only** orientation a fresh session needs — read top-to-bottom once, then refer back to specific sections.

---

## TL;DR (10 seconds)

- **Build only via `make local`** — never use the upstream commercial binary or `brew install --cask voiceink`.
- **Privacy is the bar.** Any feature touching network egress or new data sources requires explicit owner discussion.
- **Upstream does not accept PRs.** All improvements live here permanently.
- This is a **personal tool**, not a product. No commercial intent. No support obligation.

---

## Mission

The upstream VoiceInk project is excellent and actively maintained, but:

1. **Upstream explicitly does not accept PRs.** Any customization must live in a fork.
2. **Traditional Chinese workflows need adjustments** that aren't on upstream's roadmap — simplified→traditional output, Bopomofo-aware personal dictionary, zh-TW-tuned system prompts, mixed Mandarin/English handling.
3. **Self-build closes the audit gap.** Running ANY pre-built binary (open-source or not) requires trusting that the binary matches the readable source. `make local` from a freshly cloned repo removes that gap.
4. **Owner wants full control** over divergence, dependency pinning, and disabling network paths even if benign.

Owner intent: **use** voice input daily for writing and AI collaboration. NOT **build** a voice input platform. This shapes every decision — favour configuration over code, upstream features over fork divergence, simple over clever.

---

## Build and first-run

### Build from source (only sanctioned method)

```bash
# One-time setup
# 1. Install Xcode (Mac App Store, free) and open it once
# 2. Xcode → Settings → Accounts → add your Apple ID (a free Apple ID is fine;
#    Xcode auto-creates a "Personal Team" certificate)
# 3. Find your team ID and save it to .local-team (gitignored):
#    security find-identity -v -p codesigning | grep "Apple Development"
#    echo 'YOUR_TEAM_ID' > .local-team

# Regular workflow
make check       # verify toolchain
make local       # builds with your Personal Team cert; whisper.cpp framework built fresh from upstream source
make dev         # builds and relaunches the app (preferred for daily-driver iteration)
open /Applications/VoiceInk.app
```

`make local` uses `LocalBuild.xcconfig` + the `LOCAL_BUILD` Swift compilation flag. Three non-obvious consequences:

- **No paid Apple Developer account required** ($99/yr NOT needed). The build is signed with the free Apple ID "Personal Team" certificate Xcode generates automatically. This is stable across rebuilds, which means macOS keeps your Microphone / Accessibility grants instead of re-prompting after every `make local`. (Previously this fork used ad-hoc signing, which gave a fresh cdhash per build and forced TCC to re-prompt every time — now fixed.)
- **`DEVELOPMENT_TEAM` is loaded from the gitignored `.local-team` file** so personal identifiers don't end up in the public repo. The Makefile errors with a clear message if the file is missing.
- **License check is short-circuited.** `LicenseViewModel.swift:27` returns `.licensed` unconditionally under `LOCAL_BUILD`. The build will **never call `api.polar.sh`**, even on first launch. Mac serial number / hostname **never leaves the machine** via this app. This is the GPL-sanctioned free-forever path.

### First-run privacy configuration (do this before daily use)

These five settings address the actual data-egress paths confirmed by code audit:

| # | Setting | Recommended | Why |
|---|---|---|---|
| 1 | Transcription provider | **Local Whisper (whisper.cpp)** | Avoids shipping raw WAV bytes to any cloud transcription provider |
| 2 | Settings → Cleanup → Audio cleanup | **ON, 1–7 day retention** | Default is OFF — audio files accumulate forever in `~/Library/Application Support/com.prakashjoshipax.VoiceInk/Recordings/` |
| 3 | Settings → Show Announcements | **OFF** | Stops the every-4-hours GET to `beingpax.github.io/VoiceInk/announcements.json` |
| 4 | AI Enhancement | **OFF, or use Ollama** | Enhancement = transcript + selected-text + optional clipboard/screen-OCR shipped to chosen LLM |
| 5 | Accessibility permission | **Grant only if you accept the selected-text leak** (see below) | No separate toggle isolates selected-text from other AX features when AI Enhancement is on |

### Closed privacy gaps (fork-specific, no longer present)

**Selected text silent inclusion (closed by OPA-111)** — previously selected text was sent on every LLM call if Accessibility was granted, with no toggle / preview / confirmation. Now:
- Capture happens at record-start (not send-time), so the locked snapshot is what gets sent
- Privacy HUD displays the captured value before send (`docs/superpowers/specs/2026-05-22-privacy-hud-design.md`)
- New global toggle `useSelectedTextContext` (Settings → AI Models → Enhancement panel) defaults ON for backwards compat
- ESC during recording cancels everything (no LLM call, no transcribe, no paste)

**Custom vocabulary silent inclusion (closed by OPA-111)** — similar fix; new toggle `useCustomVocabularyContext`.

---

## Privacy audit summary

Performed against VoiceInk source at fork time. All findings verifiable by `grep` against this codebase.

### Network egress map — everything that leaves the device

| Host | Purpose | Trigger | Payload |
|---|---|---|---|
| User-selected cloud LLM (OpenAI / Anthropic / Groq / Gemini / OpenRouter / Mistral / Cerebras / custom) | AI Enhancement | After transcription, if AI Enhancement enabled | System prompt + transcript + optional selected-text + optional clipboard + optional screen-OCR |
| User-selected cloud transcription (Groq / Deepgram / AssemblyAI / Soniox / Speechmatics / ElevenLabs / Mistral / OpenAI / custom) | Transcription | After recording, if NOT Local Whisper | Raw WAV + language hint + optional transcription prompt |
| `api.polar.sh` | License activation | Manual click, **commercial build only** | License key + hostname + Mac serial |
| `beingpax.github.io/VoiceInk/announcements.json` | Banner fetch | Every 4 hours | GET only — no body, no ID, no user-agent personalization |
| `beingpax.github.io/VoiceInk/appcast.xml` | Sparkle update | Every 4 hours + manual | Standard Sparkle GET — `SUEnableSystemProfiling` not set, no anonymized profile |
| `huggingface.co/ggerganov/whisper.cpp/...` | Whisper model download | Manual click in Settings | GET only |
| `localhost:11434` | Ollama | If selected as provider | Local only |

**No telemetry SDK exists.** Confirmed by grep: zero hits for Sentry / Crashlytics / PostHog / Mixpanel / Amplitude / Firebase / Datadog. No on-launch ping. No on-quit beacon. No crash report uploader.

### Critical files to watch on upstream pulls

Every `git merge upstream/main` should be reviewed against these specific files. New code here = new data leaving the box.

- `VoiceInk/Services/AIEnhancement/AIEnhancementService.swift` (esp. lines ~145-200) — LLM context assembly
- `VoiceInk/Services/AIEnhancement/AIService.swift` — provider endpoint list
- `VoiceInk/Services/PolarService.swift` — any new field in activation payload
- `VoiceInk/Services/AnnouncementsService.swift` — currently GET-only; any new `httpBody` is a posture change
- `Package.resolved` — supply chain (see next section)

### Supply chain caveat

Two SwiftPM dependencies are forks owned by the upstream maintainer, pinned to `branch: main` (not a tagged version):

- `LLMkit` (Beingpax/LLMkit) — LLM provider abstraction
- `mediaremote-adapter` (Beingpax/mediaremote-adapter)

Risk: every `swift package update` pulls the latest commit from these forks. If the maintainer's GitHub account is compromised, malicious code can land here. **Mitigation**: pin to a specific commit hash in `Package.resolved`, audit before bumping (see Roadmap #3).

---

## Architecture map

### Pipeline (conceptual)

```
[Hotkey trigger] → [Record audio (AVAudioEngine)] → [Transcribe: local Whisper or cloud provider] → [text]
                                                                                                     ↓ (optional)
                                          [AI Enhancement: send transcript + assembled context to LLM]
                                                                                                     ↓
                                                                                            [enhanced text]
                                                                                                     ↓
                                                              [Paste via clipboard + Cmd+V into focused app]
```

Power Mode is a routing layer that picks which custom prompt + LLM + language to use based on the frontmost app (or browser URL via AppleScript probe).

### Key files

| Concern | Path |
|---|---|
| App entry point | `VoiceInk/VoiceInk.swift` |
| Recording state machine | `VoiceInk/Services/VoiceInkEngine.swift` |
| Cloud transcription providers (12) | `VoiceInk/Transcription/Cloud/*Provider.swift` |
| Local Whisper transcription | `VoiceInk/Transcription/Whisper/` |
| LLM enhancement pipeline | `VoiceInk/Services/AIEnhancement/AIEnhancementService.swift` |
| LLM provider implementations | `VoiceInk/Services/AIEnhancement/AIService.swift` |
| Power Mode (per-app/URL config) | `VoiceInk/PowerMode/` |
| Hotkey / shortcuts | `VoiceInk/Shortcuts/` |
| History / persistence (SwiftData) | `VoiceInk/Models/Transcription.swift` |
| Custom prompts | `VoiceInk/Models/CustomPrompt.swift` |
| Selected text reading | `VoiceInk/Services/SelectedTextService.swift` (via 3rd-party `SelectedTextKit`) |
| Screen OCR context | `VoiceInk/Services/ScreenCaptureService.swift` |
| Clipboard handling (read + restore) | `VoiceInk/CursorPaster.swift` |
| Settings UI | `VoiceInk/Views/Settings/` |
| License manager (Polar.sh) | `VoiceInk/Services/LicenseManager.swift` + `PolarService.swift` |

### Conventions to preserve

- **Code style**: SwiftUI for views, `@MainActor` + `ObservableObject` MVVM (not actor-based). Match upstream.
- **Persistence**: SwiftData for history, Keychain for API keys, UserDefaults for settings flags.
- **Concurrency**: One true `actor` (`WhisperContext`). Rest is `@MainActor`.

---

## Customization roadmap

Each item is a fork divergence. Once implemented, you own merging it across every upstream pull. Order is personal priority, not difficulty.

### 1. Privacy preview HUD (highest priority)

The known gap. Show a SwiftUI panel BEFORE each LLM send that lists every context field about to be transmitted (transcript, selected text, clipboard, screen OCR), with per-field drop/keep toggles and a countdown timeout.

**Hook point**: insert between context assembly (`AIEnhancementService.swift:~145`) and the `makeRequest` call (`~line 200`). Hold the assembled payload in an `@Observable` state, present the HUD, wait for user decision (or timeout).

**Design questions to settle before coding**:
- Modal (blocks) or non-modal (might be missed)? Recommend non-modal with audio cue.
- Default action on timeout: send, drop, or abort? Recommend abort for safety.
- Persist per-field choices across utterances? Probably no — every send is fresh.
- Configurable per prompt (some prompts auto-send, others always preview)? Probably yes.

### 2. Traditional Chinese support

- **Bundle `opencc-swift`** (or equivalent) for simplified→traditional conversion of Whisper output. Whisper-large-v3 still occasionally produces simplified characters for Mandarin input.
- **zh-TW custom prompt presets**: bundled examples for 中英混雜糾正 / 口語轉書面語 / 部落格草稿 / Slack 訊息 / 跟 AI 對話。
- **Personal dictionary Bopomofo / 注音 awareness** for proper nouns common to Taiwanese users (place names, person names, brand names).
- **Per-prompt language override** — force zh-TW transcription regardless of detected input language (useful when mixing English technical terms).

### 3. Lock supply chain

- Pin `LLMkit` and `mediaremote-adapter` in `Package.resolved` to specific commit hashes that have been audited.
- Document the audited commit + audit date in this file (append section below).
- Process rule: any bump of these requires fresh audit + this file updated.

### 4. Secret scrubber (lower priority)

Run regex-based redaction over context fields before LLM send. Built-in patterns: `sk-...`, `gsk_...`, `xoxb-...`, `gh[pousr]_...`, `AKIA...`, Luhn-validated credit cards, base64 blobs over N chars. Lower priority because:
- Users often don't know their own secrets
- Privacy preview HUD (item #1) covers the broader concern
- Mostly relevant if user routinely has secrets in clipboard / selected text

### 5. Tool execution / agentic features (deferred / probably out of scope)

Upstream has no tool_calls / function_call support. Adding it = significant code + maintenance. Deferred unless a clear daily-use need emerges.

---

## Working with upstream

### Set up upstream remote (one-time)

```bash
git remote add upstream https://github.com/Beingpax/VoiceInk.git
git fetch upstream
```

### Update from upstream (no Sparkle, by design)

```bash
git fetch upstream
git log HEAD..upstream/main --oneline                                      # see what changed
git diff HEAD upstream/main -- VoiceInk/Services/AIEnhancement/            # audit privacy-sensitive paths
git diff HEAD upstream/main -- Package.resolved                            # supply chain check
git merge upstream/main                                                     # or cherry-pick if conflicts
make local                                                                  # rebuild and test
```

**Cadence**: review upstream weekly. Prioritize security fixes. Audit before merging any commit that touches the watched files (see Privacy audit section).

### When merges become rewrites

Expected for a personal fork over time. Don't fight it — cherry-pick upstream fixes you care about, drop features you don't want. The maintainer has no obligation to stay close to upstream.

### Things that will conflict eventually

- `Models/LicenseViewModel.swift` if upstream changes trial logic
- `Services/AIEnhancement/AIEnhancementService.swift` once you add Privacy preview HUD (item #1)
- `Models/CustomPrompt.swift` if you add zh-TW preset prompts as defaults

---

## Project rules (always-on context for AI collaborators)

### Privacy is the bar

Any feature that adds a new outbound network call, reads new sensitive data (clipboard, AX, screen capture, microphone, file system beyond app sandbox), or modifies the context payload sent to LLM **MUST be discussed and explicitly approved** before implementation. Default position: minimize data egress.

Before proposing any change, ask:
- Does this send anything new over the network? If yes, can the user see/audit what?
- Does this read anything new from the system? If yes, why and where does it go?
- Could this leak something the user doesn't expect?

### Build = test

Every change must pass `make local && open /Applications/VoiceInk.app && <manual smoke>`. Unit tests run via `xcodebuild test` (when applicable). No "I assume it works" without verification.

### Upstream divergence is a cost

Before adding any feature, ask: "Could this be done with a config setting upstream already exposes?" If yes, prefer that. Diverging from upstream means manual merging forever.

### GPL v3 obligations

This fork is GPL v3 (same as upstream). Any code added must be GPL-compatible. Any binary distributed must offer source. **No proprietary code, no closed-source dependencies, no API keys in source.**

### Keep the public repo public-safe

This repo is public on GitHub. **Do not commit**:
- API keys for any provider (OpenAI, Anthropic, Groq, Polar, etc.)
- License keys (VoiceInk's own license keys if any)
- Personal information beyond what's already in git history (real names, emails, addresses)
- Anything from `~/Library/Application Support/com.prakashjoshipax.VoiceInk/` (audio recordings, transcripts, history)
- Personal prompt content that reveals private workflows
- Internal Slack/Discord screenshots or transcripts

`.gitignore` covers most. Verify before any commit touching new paths.

### Dog-fooding loop (the actual workflow)

The owner uses this app daily. The intended improvement cycle:

1. Notice friction during real use → write it down (note app, issue tracker, anywhere)
2. Triage: is it a config tweak, a fork patch, an upstream feature request, or "live with it"?
3. If patch: keep it small, isolated, test in daily use for ≥3 days before merging to main
4. If something breaks: revert immediately, debug separately

Friction symptoms that warrant a fork patch:
- "I have to click X every time" → ergonomic improvement
- "I worry about what was sent" → privacy posture (HIGHEST priority)
- "It produces wrong output for Mandarin" → zh-TW improvement
- "I want different behavior in [specific app]" → Power Mode rule, not code

### Anti-patterns to avoid

- **Don't reimplement features upstream already has.** Read upstream code first (see Architecture map).
- **Don't add OS-level systems programming work** (CGEventTap, AX walking, NSPanel lifecycle) without clear daily-use benefit. Owner specifically wants less of this kind of work.
- **Don't add subscription / commercial logic.** This is personal-use GPL.
- **Don't disable upstream features by deletion** — prefer config flags so future merges are easy.
- **Don't introduce new SwiftPM dependencies casually** — supply chain matters.

---

## Background context (read once, reference later)

The owner evaluated multiple voice input tools before forking. Findings (factual, don't re-evaluate):

- **Closed-source paid tools** (e.g., ZeroType by a popular Taiwanese .NET MVP): can't audit privacy posture, can't customize for personal niche. Rejected on principle.
- **Handy** (`cjpais/Handy`): Tauri/Rust + webview, cross-platform. Wrong stack for native macOS feel. Has same silent-LLM-send issue as VoiceInk.
- **Building from scratch**: attempted for several weeks. Architecture was sound (actor-based pipeline, multi-prompt YAML system, privacy preview HUD design) but the project's daily work shape (CGEventTap, AX, NSPanel, AppKit lifecycle) conflicted with the owner's actual goal — using voice input, not becoming a macOS systems programmer.
- **VoiceInk**: closest fit. Privacy posture verifiable (open source, no telemetry, audited cleanly). The selected-text-via-AX gap is a known fork patch target.

The fork is the resolved conclusion of this evaluation. Don't re-litigate.

---

## Status

| | |
|---|---|
| Upstream | [`Beingpax/VoiceInk`](https://github.com/Beingpax/VoiceInk) (GPL v3, no PRs accepted upstream) |
| This fork | [`opass/VoiceTwInk`](https://github.com/opass/VoiceTwInk) |
| Fork created | 2026-05-22 |
| License | GPL v3 (inherited; cannot change) |
| Build method | `make local` only (see Build section) |
| Personal use | Active daily driver (post first-run config) |
| Open issues from upstream | https://github.com/Beingpax/VoiceInk/issues |

---

## Append-only log (notable fork-specific decisions)

Update this section as decisions get made. Useful when reviewing why something diverges from upstream.

- **2026-05-22**: Fork created. Built initially from upstream HEAD. First-run config applied per recommendations above.
- **2026-05-22**: OPA-108 — 新增 "Chinese (Taiwan)" 語言選項。內部用 BCP-47 `zh-TW`、送 Whisper API 前透過 `LanguageDictionary.whisperLanguageCode(for:)` helper 翻成 `zh`（Whisper 不接受 region tag）。對應 seed prompt 在 `WhisperPrompt.languagePrompts["zh-TW"]`（v3 台灣繁中自然句）。改動：`LanguageDictionary.swift`、`CloudTranscriptionService.swift:selectedLanguage()`、`Transcription/Whisper/LibWhisper.swift`、`Transcription/Whisper/WhisperPrompt.swift`。既有「Chinese」(zh) 選項保留不動（仍用上游 default 簡中 hello-句 seed prompt）。Spike 記錄見 Linear OPA-107，scoping 決策見 OPA-108 comments。
- **2026-05-22**: Build 簽章從 ad-hoc 改為 hybrid「ad-hoc 整個包 + 對外層 .app 重簽 Apple Development cert」。動機：ad-hoc 每次 build 的 cdhash 都不同，macOS TCC 因此把每個 build 看成新 app、重新要求授權麥克風 / Accessibility。SPM 套件（mediaremote-adapter 等）的 auto-generated build target 對 Apple Development cert 不友善（會掉到舊 default "Mac Development" 找不到 cert），所以 build 階段仍是 ad-hoc；完成後 Makefile 對外層 `.app` 再跑一次 `codesign --force --sign "Apple Development:..."`（不用 `--deep`，frameworks 保留 ad-hoc 簽章）。TCC 只看外層 .app 的 designated requirement，這條 = 「Apple Development cert + 你的 team」是 rebuild 之間穩定的，因此權限不會掉。改動：`LocalBuild.xcconfig`（註解說明 hybrid 策略）、`Makefile`（從 gitignored `.local-team` 讀 team ID、build 後跑 codesign 重簽 wrapper、新增 `relaunch` target、`dev = local + relaunch`、deploy 路徑從 `~/Downloads` 改 `/Applications`（前提：上游商業 binary 已不在那邊；CLAUDE.md mission 本來就規定不裝），並自動清理 `~/Downloads/VoiceInk.app` 與 `~/Applications/VoiceInk.app` 兩處遷移殘留）、`.gitignore`（排除 `.local-team`）、`CLAUDE.md` 對應段落更新。一次性 setup 需在 Xcode 加 Apple ID + 寫 team ID 到 `.local-team`。仍是 $99/yr 不需付的免費路徑。
- **2026-05-22 / 2026-05-23**: OPA-111 / OPA-112 / OPA-113 — Privacy HUD landed. Capture-at-record-start architecture: selected text + custom vocabulary moved from send-time fetch to record-start capture, alongside clipboard / screen / system context. New `PrivacyHUDPanel` floats adjacent to active recorder (MiniRecorder above / Notch below), shows every field about to be sent, ESC cancels mid-recording. System context (time / timezone / day-of-week / locale) bundled as `<SYSTEM_CONTEXT>` in system message — Assistant Mode can now answer "what time is it". Two new global toggles (`useSelectedTextContext`, `useCustomVocabularyContext`) close the previous silent-inclusion gap. `getSystemMessage()` reads captured properties first with on-demand fallback so HUD failures don't break enhance pipeline. Spec: `docs/superpowers/specs/2026-05-22-privacy-hud-design.md`. Plan: `docs/superpowers/plans/2026-05-22-privacy-hud.md`. 13 implementation commits on branch `feat/privacy-hud`.
- **2026-05-24**: OPA-115 — 新增 "Simulate Typing Instead of Paste" Settings toggle（Recording Feedback section, default OFF）。打開時 `CursorPaster.performPasteSession` 走新增的 `typeAtCursor()` 路徑，逐字用 `CGEventKeyboardSetUnicodeString` 注入（5ms inter-char delay），繞過 IME（注音輸入法 active 時不被攔截）。同步在 `TranscriptionPipeline.swift:228` AutoSend 觸發點加 gate：typing mode ON 時強制不發 Enter，使用者先檢視 transcript 再手動送出。動機：解決 Claude Code CLI 對大段 paste 自動收摺成 `[Pasted text +N lines]` 導致無法 inline 編輯的問題。改動：`CursorPaster.swift`、`TranscriptionPipeline.swift`、`SettingsView.swift`、`AppDefaults.swift`。Probe 結果：**成功**。owner 實測 Claude CC 內 typing 速度夠快、`[paste]` 摺疊問題確實繞開、inline 可編輯。Spec: `docs/superpowers/specs/2026-05-24-simulate-typing-mode-design.md`. Plan: `docs/superpowers/plans/2026-05-24-simulate-typing-mode.md`. 4 implementation commits on branch `feat/simulate-typing-mode`. Dogfood 過程附帶發現 Privacy HUD 在 success 路徑的 race（OPA-116, 待修）— 跟此 feature 無關、不延後 ship。
- **2026-05-24**: OPA-116 — Privacy HUD success-path race 修掉。原本 capture Task 在 OCR 完成後只用 `!shouldCancelRecording` guard，protect 了 cancel 路徑（OPA-112 設計範圍）但**沒**覆蓋 success 路徑：短錄音（< 2 秒）釋放時，`finishRecorderSession` 已把 HUD 清掉，stale OCR 才回來、`assemblePrivacyPayload()` 又把 `currentPrivacyPayload` 寫回 non-nil → HUD 復活、沒有第二次 clear path、卡死直到 quit。Fix：在 capture Task 開頭 snapshot `activeRecordingStartID`，assemble 前檢查仍相符。`activeRecordingStartID` 已是現成的 session lifecycle token — record start (line 141) 設新 UUID、success 釋放 (line 98) 跟所有 cancel/error 路徑都會清 nil，stale OCR 回來 ID 對不到就 skip。改動 1 個檔案 `VoiceInk/Transcription/Engine/VoiceInkEngine.swift`（+10/-8 lines）。Owner 實測 short / long / cancel 三種 scenario 都正常。1 commit on branch `fix/opa-116-privacy-hud-success-race`。
