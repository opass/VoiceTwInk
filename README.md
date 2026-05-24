<div align="center">
  <img src="VoiceInk/Assets.xcassets/AppIcon.appiconset/256-mac.png" width="180" height="180" />
  <h1>VoiceTwInk</h1>
  <p>Privacy-auditable, Traditional Chinese tuned, build-from-source-only fork of VoiceInk.</p>

  [![License](https://img.shields.io/badge/License-GPL%20v3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
  ![Platform](https://img.shields.io/badge/platform-macOS%2014.0%2B-brightgreen)
  [![Fork of](https://img.shields.io/badge/fork%20of-Beingpax%2FVoiceInk-orange)](https://github.com/Beingpax/VoiceInk)

  <p><strong>繁體中文版</strong> → <a href="./README.zh-TW.md">README.zh-TW.md</a></p>
</div>

---

## TL;DR

VoiceTwInk is a personal fork of [VoiceInk](https://github.com/Beingpax/VoiceInk), a macOS voice-to-text app. Upstream is excellent but explicitly does not accept PRs, so this fork exists to add privacy auditability, Traditional Chinese (Taiwan) tuning, and ergonomic fixes for tools like Claude Code CLI. **Build-from-source only — no pre-built binary, no license required.**

## What this fork adds

### 1. Privacy HUD — see every byte before it leaves

Upstream's AI Enhancement silently bundles selected text, clipboard, screen-OCR output, and custom vocabulary into every LLM request when Accessibility permission is granted. You can't audit what's about to be sent — it just goes.

VoiceTwInk adds a floating HUD that appears alongside the recorder during dictation and shows every context field about to leave the box, with a visual marker (green / yellow) for local-vs-cloud destination. Press ESC mid-recording to cancel everything before any data is sent. New global toggles let you opt out of selected-text and custom-vocabulary inclusion entirely.

Details: [FORK-CHANGES.md § 1. Privacy HUD](./FORK-CHANGES.md#1-privacy-hud).

### 2. Traditional Chinese tuning

Whisper's default Chinese output is Simplified, and cloud LLMs often normalize Traditional Chinese back to Simplified when input is short. VoiceTwInk addresses both layers:

- A new "Chinese (Taiwan)" language option in Settings, backed by a Taiwan-specific seed prompt that biases Whisper toward 繁體中文 + Taiwan vocabulary (`捷運` not `地铁`, `軟體` not `软件`, etc.)
- The default enhancement prompt now includes a top-priority `[CRITICAL LANGUAGE RULE]` block that forces LLM output to Traditional Chinese, with concrete character pairs as examples

**Recommended setting**: language = **Auto-detect** + AI Enhancement on. The "Chinese (Taiwan)" Whisper seed prompt is aggressive enough to force English audio into Chinese (an unintended side-effect); auto-detect bypasses this, and the enhancement-layer rule still converts any Simplified output to Traditional.

Details: [FORK-CHANGES.md § 2. Traditional Chinese tuning](./FORK-CHANGES.md#2-traditional-chinese-tuning).

### 3. Build from source by default

Upstream's open-source model: code is fully open, but the licensed commercial binary buys you automatic updates and support. This fork has no license server — `make local` from a clean clone gives you a working, properly-signed app forever, free.

The build is signed with a free Apple Developer Personal Team certificate (no $99/yr account needed), which means macOS TCC retains your Microphone / Accessibility permissions across rebuilds — fixing the previous pain where every rebuild counted as a fresh app and re-prompted for all permissions.

```bash
make check       # verify Xcode setup
make local       # build + deploy to /Applications/
make dev         # build + relaunch running VoiceInk (preferred for daily iteration)
```

Details: [BUILDING.md](./BUILDING.md) for first-time setup, [CLAUDE.md → Build and first-run](./CLAUDE.md#build-and-first-run) for the hybrid signing rationale.

### 4. Simulate Typing Mode — bypass Claude Code CLI's `[Pasted text]` collapse

Claude Code CLI auto-collapses any large paste into `[Pasted text +N lines]`, making inline review impossible before submitting. VoiceTwInk adds a Settings toggle that swaps the paste pipeline for per-character `CGEventKeyboardSetUnicodeString` injection, simulating real typing.

When enabled, the toggle also:
- **Bypasses macOS IME** — 注音 / Bopomofo input methods do not intercept the injected characters
- **Force-disables AutoSend** — review and edit the transcript before manually pressing Enter
- **Translates `\n` to Shift+Return** — preserves paragraph structure without prematurely submitting in chat-style apps like Slack, Discord, Claude Code CLI

Details: [FORK-CHANGES.md § 4. Simulate Typing Mode](./FORK-CHANGES.md#4-simulate-typing-mode).

### 5. GPL v3, forever

Upstream is GPL v3 and so is this fork. Every change must remain open source — for a privacy-focused tool, that's a feature, not a bug. You can fork this fork and audit anything; there is no proprietary code path, no hidden telemetry, no closed-source dependency that could change posture under your feet.

Details: [LICENSE](./LICENSE), [CLAUDE.md → GPL v3 obligations](./CLAUDE.md#gpl-v3-obligations).

## Privacy posture

This fork preserves upstream's open-source, no-telemetry posture and adds runtime audit visibility.

Network egress at a glance:

| Host | Trigger | Payload |
|---|---|---|
| Cloud LLM (user-selected) | AI Enhancement enabled | system prompt + transcript + chosen context fields |
| Cloud transcription (user-selected) | not using Local Whisper | raw WAV + optional prompt |
| `huggingface.co` | manual Whisper model download | GET only |
| `beingpax.github.io` | Sparkle update check + announcements | GET only, no body, no UA personalization |
| `api.polar.sh` | license activation | **commercial build only — never called in `make local` builds** |

No telemetry SDK exists (verified by `grep` for Sentry / Crashlytics / PostHog / Mixpanel / Amplitude / Firebase / Datadog: zero hits). No on-launch ping, no on-quit beacon, no crash uploader.

Full audit: [CLAUDE.md → Privacy audit summary](./CLAUDE.md#privacy-audit-summary).

## Build & first-run

Prerequisites:
- Xcode (free, from Mac App Store) with your Apple ID added under Settings → Accounts — this creates the Personal Team cert
- A `.local-team` file in the repo root containing your Apple Developer Team ID (this file is gitignored)
- macOS 14.0 or later

```bash
make check       # verify toolchain
make local       # build + deploy to /Applications/
make dev         # build + relaunch running app
```

After first launch, configure these for the fork's intended privacy posture:
1. Transcription provider: **Local Whisper** (avoids cloud audio upload)
2. Settings → Cleanup → Audio cleanup: **ON** (default OFF; audio files otherwise accumulate forever)
3. Settings → Show Announcements: **OFF** (stops 4-hour polling to `beingpax.github.io`)
4. AI Enhancement: **OFF**, or use **Ollama** (avoids cloud LLM transcript upload)

Detailed setup including TCC permission gotchas: [BUILDING.md](./BUILDING.md). Full project rationale: [CLAUDE.md](./CLAUDE.md).

## For Traditional Chinese users

Recommended:
- **Language**: Auto-detect (not "Chinese (Taiwan)" — see [FORK-CHANGES.md § 2 known trade-offs](./FORK-CHANGES.md#2-traditional-chinese-tuning) for why)
- **AI Enhancement**: On (this is what enforces 繁體中文 output)
- **Optional**: build a Custom Prompt for your domain vocabulary (teammate names, project codenames, etc.)

With these settings, mixed Chinese + English voice input is handled naturally — e.g., 「我覺得這個 implementation 很 elegant」 stays mixed, English technical terms preserved verbatim.

## Status & scope

- Personal fork, daily driver for the owner.
- No SLA, no support, no release schedule. Pull `main` and rebuild.
- Issues welcome as a way to track shared interest. PRs may be slow or declined if they don't fit the fork's mission (privacy-first, zh-TW, build-from-source).
- See [CLAUDE.md](./CLAUDE.md) for the full project context — that file is the source of truth for what this fork is and isn't.

## Upstream

Built on top of [Beingpax/VoiceInk](https://github.com/Beingpax/VoiceInk) (GPL v3). Upstream's README explicitly states it does not accept PRs; this fork exists to allow personal customization without that constraint. No ill will toward upstream — it's a polished, well-engineered app and this fork inherits every good decision its maintainer made.

Sync cadence: weekly review of upstream `main`, prioritizing security fixes and audit-sensitive paths.

## License

GPL v3 (inherited from upstream; cannot change). See [LICENSE](./LICENSE).

## Acknowledgments

### Upstream

- [Beingpax/VoiceInk](https://github.com/Beingpax/VoiceInk) — original work this fork builds on

### Core technology

- [whisper.cpp](https://github.com/ggerganov/whisper.cpp) — high-performance inference of OpenAI's Whisper model
- [FluidAudio](https://github.com/FluidInference/FluidAudio) — Parakeet model implementation

### Essential dependencies

- [Sparkle](https://github.com/sparkle-project/Sparkle) — update framework (this fork pulls latest source manually instead)
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) — user-customizable shortcuts
- [LaunchAtLogin](https://github.com/sindresorhus/LaunchAtLogin)
- [MediaRemoteAdapter](https://github.com/ejbills/mediaremote-adapter)
- [Zip](https://github.com/marmelroy/Zip)
- [SelectedTextKit](https://github.com/tisfeng/SelectedTextKit)
- [Swift Atomics](https://github.com/apple/swift-atomics)
