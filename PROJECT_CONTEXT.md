# Mirror — Project Context

## What It Is

Mirror is a macOS desktop app that records your screen, keystrokes, and mouse activity while you perform a manual workflow, then uses AI (Claude/GPT-4o via OpenRouter) to analyze the behavioral trace and generate a persistent scheduled automation. It deploys workflows as launchd jobs that run on a repeating cron schedule.

**One-line:** "Record once, review, deploy — runs automatically on schedule."

**Repo:** https://github.com/jameserez-code/mirror

---

## Tech Stack

| Layer | Technology |
|---|---|
| Language | Swift 5.9 |
| Platform | macOS 13+ (ScreenCaptureKit requires 12.3+) |
| Build | Swift Package Manager via `Package.swift` |
| UI | AppKit + WKWebView hosting vanilla HTML/CSS/JS (no frameworks) |
| Screen capture | Apple ScreenCaptureKit + CGEventTap |
| OCR | Apple Vision framework (VNRecognizeTextRequest) |
| AI | OpenRouter (default), Anthropic direct, OpenAI GPT-4o |
| Credentials | macOS Keychain via `CredentialStore.swift` |
| Scheduling | launchd plists in `~/Library/LaunchAgents/` |
| Execution | Custom local runner + CGEvent posting for replay |
| Distribution | Direct `.app` bundle via `build.sh`, self-signed, not App Store |

---

## File Map (16 source files + 2 HTML)

```
Mirror/
├── Package.swift                    # SwiftPM config
├── build.sh                         # Build + bundle + codesign + install
├── entitlements.plist               # App Sandbox disabled, ScreenCapture + AppleEvents
├── .gitignore                       # .build/, Sessions/, Data/, Logs/
├── scripts/create-dev-cert.sh       # Self-signed code signing identity
│
├── Mirror/
│   ├── main.swift                   # Entry point: GUI or headless --run-workflow
│   ├── AppDelegate.swift            # NSMenu bar, status item, permissions prompt
│   ├── FullWindowController.swift   # WKWebView bridge (all JS↔Swift message routing)
│   ├── CaptureManager.swift         # Orchestrates ScreenRecorder + EventTapManager
│   ├── ScreenRecorder.swift         # ScreenCaptureKit wrapper, 1fps PNG frames
│   ├── EventTapManager.swift        # CGEventTap for keyboard/mouse/clipboard
│   ├── AnalysisPipeline.swift       # AI API calls (3 providers), prompt, JSON parser
│   ├── WorkflowEngine.swift         # Deploy, execute (20 action types), launchd, cron
│   ├── SessionPackager.swift        # .mirrorpack zip bundles, timeline builder
│   ├── ScreenOCR.swift              # Vision-based text extraction from frames
│   ├── N8nExporter.swift            # Workflow → n8n JSON converter
│   ├── PermissionsManager.swift     # Accessibility + Screen Recording checks
│   ├── CredentialStore.swift        # Keychain API key / OAuth token storage
│   ├── Settings.swift               # UserDefaults wrapper
│   ├── HistoryStore.swift           # Run history persistence
│   ├── ui.html                      # Main window UI (idle→record→analyze→review→deploy)
│   └── settings.html                # Settings window (API keys, permissions, workflows, activity)
```

---

## Feature Flow (all implemented)

1. **Record** — screen video (1fps PNGs) + keystrokes + mouse + clipboard changes + browser URLs. Secure field redaction (AXSecureTextField). Escape key to stop.
2. **Package** — events JSON + metadata + OCR frame context → `.mirrorpack` zip bundle.
3. **Analyze** — AI receives structured activity timeline + OCR text. Returns structured `Workflow` JSON.
4. **Review** — UI shows workflow steps with Plain English descriptions, confidence bar, schedule picker, step checkboxes, data flow indicators, review-required badges.
5. **Deploy** — creates launchd plist at `~/Library/LaunchAgents/com.mirror.workflow.<uuid>.plist`, persists to `~/Mirror/Data/workflows.json`, schedules via StartCalendarInterval.
6. **Execute** — headless mode (`--run-workflow <id>`) runs steps sequentially with variable resolution, condition evaluation, CGEvent replay.
7. **Export** — n8n-compatible JSON with proper node type mapping.

---

## 20 Action Types

`open_url`, `open_application`, `type_text`, `press_shortcut`, `click`, `wait`, `copy_clipboard`, `paste_text`, `extract_data`, `web_request`, `send_email`, `file_read`, `file_write`, `run_script`, `screenshot`, `condition`, `transform`

(17 active — `scroll` was removed as it wasn't in the AI's action vocabulary.)

---

## What Was Recently Fixed (18 items — all compiled clean)

### Critical (crashes)
1. **SIGSEGV crash** — `FullWindowController` had no `deinit`. `WKUserContentController.add(self...)` created retain cycle with WKWebView config. When window closed during in-flight JS message → dispatch to freed memory → crash. Fixed: added `deinit` removing both script message handlers + invalidating timer + removing event monitor + cancelling analysis task.
2. **EventTapManager UAF** — `Unmanaged.passUnretained(self).toOpaque()` passes raw pointer to C callback. No `deinit` disabled the tap. Fixed: added `deinit` calling `stopCapture()`.
3. **Headless mode hang** — `semaphore.wait()` with no timeout in `main.swift`. If engine completion never fires, process hangs forever. Fixed: 5-minute safety timeout fallback.
4. **extract_data force-unwrap crash** — `String(source[Range(match.range, in: source)!])` crashed if regex had no matching groups. Fixed: optional binding.

### Security
5. **RCE via run_script** — AI-generated `run_script` steps ran `/bin/bash -c` with no restrictions. Fixed: command allowlist (`curl`, `osascript`, `open`, `shortcuts`, etc.), unknown commands blocked + logged.

### Correctness
6. **callJS escaping broken** — manual escaping (order-dependent `\` then `'`) broke for JSON payloads containing single quotes. Fixed: base64-only path with JS-side `try/catch`.
7. **URLSession timeouts** — no explicit timeouts on 3 AI provider calls. Fixed: 120s request / 300s resource timeouts via custom `URLSessionConfiguration`.
8. **Screen stream errors** — no `SCStreamDelegate.didStopWithError` handler, stream failures were silent. Fixed: added handler logging errors and setting `isRecording = false`.
9. **Frame processing on main thread** — expensive CIImage → CGImage → PNG pipeline ran on `.main`. Fixed: moved to background utility queue.
10. **workflow.enable handler missing** — `settings.html` sent `workflow.enable` but `FullWindowController` had no handler. Fixed: added handler calling `workflowEngine?.enable(workflowId:)`.

### Robustness
11. **Thread safety** — `stepOutputs` dictionary shared across concurrent workflow executions with no synchronization. Fixed: `NSLock` with `stepOutputValue`/`stepSetOutputValue`/`stepOutputsSnapshot` helpers.
12. **Cron `*/N` parsing** — `Int("*/5")` returned nil, dropping schedule fields silently. Fixed: custom `parseCronField` handling `*/N` interval notation.
13. **developerExtrasEnabled** — Web Inspector enabled in production builds. Fixed: gated behind `#if DEBUG` in both web views.
14. **Delete confirmation** — workflow delete in settings was one-click with no undo. Fixed: `confirm()` dialog before sending `workflow.delete`.
15. **Action validation** — AI-generated unknown actions silently succeeded at runtime. Fixed: `validActions` set check at parse time, unknown actions rejected with error.
16. **Image pipeline** — wasteful CIImage→NSImage→TIFF→NSBitmapImageRep→PNG roundtrip. Fixed: direct `NSBitmapImageRep(cgImage:)` → PNG.
17. **UserDefaults.synchronize()** — called unnecessarily on every setter (no-op since macOS 10.15). Removed all 6 calls.
18. **Dead scroll code** — unreachable `case "scroll"` in `executeStep`. Removed.

---

## Current State

| Aspect | Status |
|---|---|
| **Compiles** | Clean, zero warnings |
| **Git** | 1 commit on `master`, pushed to GitHub |
| **UI** | Complete flow: idle → record → analyze → review → deploy |
| **Recording** | Working (one test session: 9.76s, 3,920 events, 7 frames) |
| **AI analysis** | 3 providers implemented, response parsing with fallback patching |
| **Deployment** | launchd plist creation + scheduling works |
| **Execution** | Headless mode, 17 action types, variable resolution, conditions |
| **Export** | n8n JSON export to ~/Downloads |
| **Deployed workflows** | None (workflows.json is empty array) |

---

## Known Remaining Gaps

### Architecture
- **No protocols / DI** — everything is concrete classes with singletons. Untestable without refactoring.
- **No automated tests** — zero test files.
- **No CI/CD** — no GitHub Actions or build automation.
- **Flat file structure** — no modules, no package separation. All Swift files in one directory.

### Reliability
- **ScreenRecorder**: `stream(_:didStopWithError:)` exists now but no automatic recovery/restart.
- **All writes use `try?`** — silent failures when disk full (SessionPackager, WorkflowEngine, etc.).
- **Clipboard polling**: only explicit, no timer — clipboard changes between polls may be missed.
- **No retry on API errors**: 429 (rate limit) and 5xx errors fail immediately.
- **No token budget tracking**: large recordings can produce expensive AI prompts with no warning.
- **Browser URL reading blocks event tap thread** — freezes input if browser is unresponsive to Accessibility API.

### Execution
- **No concurrent step execution** — all steps run sequentially.
- **No step timeout** — a hung process (e.g., `open_application` waiting on a non-responsive app) blocks the entire workflow.
- **click at (0,0) fallback** — if coordinate parsing fails, clicks Dock/menu bar.
- **Variable resolution** supports only `{{word}}` — no nested paths like `{{step1.field}}`.
- **launchd path is hardcoded** to `/Applications/Mirror.app/Contents/MacOS/Mirror`.
- **Double-restore bug**: running headless while GUI is active creates two engines sharing `workflows.json`.

### UI
- **No keyboard navigation** — no tabindex, ARIA roles, or accessibility in HTML.
- **No loading states for initial bridge connection**.
- **No offline/bridge-disconnected state handling**.
- **Toast system overwrites** on multiple rapid errors.

### Security
- **run_script allowlist** is permissive — `/usr/bin/osascript` gives full AppleScript power.
- **open_url** opens any URL including `file:///` paths.
- **copy_clipboard** overwrites user clipboard without warning.
- **App Sandbox disabled** (required for CGEventTap, launchctl) — full user privileges.
- **OAuth is V1 only** — manual browser flow, no PKCE.

### Build
- **Ad-hoc code signing** on fallback — Accessibility permission resets on every rebuild without persistent "Mirror Dev" identity.
- **No notarization** — can't distribute outside direct download (Gatekeeper warns).

---

## Potential Future Directions

### Short-term (polish what exists)
- Add CI (GitHub Actions: `swift build` on push)
- Create test target in `Package.swift`
- Add step timeouts in WorkflowEngine
- Add retry with exponential backoff on AI API errors
- Add token budget check before sending large prompts
- Fix clipboard polling to use a timer within CaptureManager
- Filter `file:///` URLs from `open_url` action
- Add step execution timeout (e.g., 30s default per step)
- UserNotifications permission request on first launch

### Medium-term (expand capability)
- **Multi-modal AI** — send sampled frames as images to vision-capable models (GPT-4o, Claude) for visual pattern recognition instead of OCR-only.
- **Firebase sync** — cloud backup/restore of workflows, cross-device sync.
- **PKCE OAuth** — upgrade OAuth flow for Google/Microsoft/Notion API integrations that need tokens.
- **n8n direct integration** — deploy directly to a local or cloud n8n instance via its REST API.
- **Workflow templates** — pre-built workflows for common tasks (email digest, CRM update, report generation).
- **Recording controls** — pause/resume during recording, crop recording area.

### Long-term (product evolution)
- **Agent mode** — instead of replaying exact steps, have the AI dynamically adapt the workflow based on current screen state (computer-use agent pattern).
- **Shared workflow library** — community-contributed workflows, import/export.
- **Workflow editor** — visual drag-and-drop workflow builder complementing the record-first approach.
- **Trigger types beyond schedule** — file watcher (fsevents), email received (Mail.app plugin), webhook listener.
- **Analytics dashboard** — workflow run success rates, duration trends, failure patterns.
- **iOS companion** — monitor/manage workflows from phone.
- **App Store distribution** — conditionalize features requiring sandbox-off (replay via Shortcuts instead of CGEvent) for App Store compliance.
