# Mirror — Complete Technical Architecture

## What Mirror Is

A macOS desktop app (Swift + AppKit + WKWebView) that records a user's screen, keystrokes, and mouse activity, then uses AI to generate a scheduled workflow automation from that recording. The workflow can be edited visually, deployed as a launchd job (cron), and executed either via cloud APIs (Gmail, Sheets, Slack, Drive) or desktop replay (CGEvent).

**Tech Stack:** Swift 5.9, macOS 13+, AppKit, WKWebView, ScreenCaptureKit, CGEventTap, Vision OCR, OpenRouter AI (default), Keychain, launchd.

**Repo:** https://github.com/jameserez-code/mirror

**Build:** `./build.sh` → installs to `/Applications/Mirror.app`
**Bundle ID:** `com.mirror.app`

---

## File Map (36 files)

### App Shell
| File | Lines | Purpose |
|---|---|---|
| `main.swift` | ~30 | Entry point. GUI mode starts NSApplication. Headless mode (`--run-workflow <id>`) executes via WorkflowEngine. |
| `AppDelegate.swift` | ~180 | NSApplicationDelegate. Menu bar status item, permissions prompt, window management. Holds strong ref to `workflowEngine`. |
| `FullWindowController.swift` | ~890 | **The bridge.** NSWindowController + WKScriptMessageHandler. All JS↔Swift communication flows through `userContentController(didReceive:)`. Manages: main window (ui.html), settings window (settings.html), recording lifecycle, AI analysis, deploy, bridge handlers for ~30 message types. |
| `Package.swift` | ~30 | SwiftPM config. Single executable target. Resources: ui.html, settings.html. Linked frameworks: AppKit, WebKit, ScreenCaptureKit, Security, CoreGraphics, Vision. |

### Capture Stack
| File | Purpose |
|---|---|
| `CaptureManager.swift` | Orchestrates ScreenRecorder + EventTapManager. `startCapture()` / `stopCapture()` / `packageSession()`. Singleton. |
| `ScreenRecorder.swift` | ScreenCaptureKit wrapper. 1fps PNG frames, background utility queue. `SCStreamDelegate` for error handling. |
| `EventTapManager.swift` | CGEventTap for keyboard/mouse/clipboard/browser URL. `.listenOnly` (passive). Has `deinit` that calls `stopCapture()`. Secure field redaction via AXSecureTextField. |
| `ScreenOCR.swift` | Vision framework OCR on captured frames. Used for context enrichment. |

### Intelligence Stack (5 layers, run in sequence)
| Layer | File | Input → Output |
|---|---|---|
| 1. Semantic Actions | `SemanticActionExtractor.swift` | `CapturedEvent[]` → `SemanticAction[]` (gmail_search, sheets_append, type_text, etc.) |
| 2. Workflow Intent | `WorkflowIntentExtractor.swift` | `SemanticAction[] + ExtractedArtifact[]` → `WorkflowIntent` (objective, domain) |
| 3. Workflow Graph | `WorkflowGraphBuilder.swift` | `SemanticAction[] + Artifacts + Intent` → `WorkflowGraph` (nodes + edges) |
| 4. Entity Graph | `EntityGraphBuilder.swift` | `Events + Actions + Artifacts` → `EntityGraph` (Invoice, Amount, Vendor, etc.) |
| 5. Belief State | `BeliefStateEngine.swift` | All of the above → `BeliefState` (unified probabilistic model of intent, entities, strategy) |

### AI Analysis
| File | Purpose |
|---|---|
| `AnalysisPipeline.swift` | System prompt builder + 3 API providers (OpenRouter, Anthropic, OpenAI). Parses AI JSON response into `Workflow` struct. Includes cloud action detection prompt for Gmail/Sheets. Validates action types at parse time. Timeout: 120s. |
| `SessionPackager.swift` | Builds `.mirrorpack` zip bundles. Builds activity timeline text for AI prompt. |

### Execution & Reliability
| File | Purpose |
|---|---|
| `WorkflowEngine.swift` | CRUD for deployed workflows. executeWorkflow() with 25+ action types including gmail_send, sheets_append, slack_post. launchd plist management. Cron parsing with */N patterns. Thread-safe stepOutputs with NSLock. |
| `ReliableWorkflowRunner.swift` | **Production execution.** Per-node timeouts (30s). Exponential retry (3x, 2^n backoff). Approval nodes. Run history persistence (500 runs to JSON). Workflow health metrics (success rate, time saved, failures). Notifications. |

### API Connectors (5)
| File | Purpose |
|---|---|
| `GoogleOAuthManager.swift` | PKCE OAuth 2.0 flow for Google. Opens browser, runs localhost:8765 callback server, exchanges code for tokens, auto-refreshes. Stores in Keychain via `CredentialStore`. Covers all Google scopes (gmail.send, gmail.readonly, spreadsheets, drive.file). |
| `GmailConnector.swift` | `send()`, `search()`, `fetchMessage()` via Gmail API. HTTP status checking. |
| `SheetsConnector.swift` | `appendRow()`, `readRange()`, `createSheet()`, `extractSpreadsheetId()`. |
| `DriveConnector.swift` | `uploadFile()`, `downloadFile()`, `searchFiles()`, `shareFile()`. |
| `SlackConnector.swift` | `postMessage()`, `uploadFile()`, `fetchMessages()`. Uses OAuth token from Keychain. |

### Evaluation & Learning
| File | Purpose |
|---|---|
| `WorkflowEvaluationEngine.swift` | GroundTruthRecord, FailureType taxonomy (6 categories), diff engine, confidence calibration, root cause attribution, DebugBundle output. |
| `FailureToImprovementCompiler.swift` | Pattern mining, failure signatures, synthesized rules, patch simulation, continuous learning loop. |
| `OutcomePolicyEngine.swift` | Contextual bandit strategy optimization. Hypothesis probability distributions. Epsilon-greedy exploration. |

### Infrastructure
| File | Purpose |
|---|---|
| `CredentialStore.swift` | macOS Keychain wrapper. Generic `save(key:value:)` / `get(key:)` / `delete(key:)`. Also has API-key-specific methods. |
| `Settings.swift` | UserDefaults wrapper for provider, model, API key presence markers. `loadHTML()` for bundling HTML resources. |
| `HistoryStore.swift` | Append-only run history log (older system, partially superseded by RunHistoryStore in ReliableWorkflowRunner). |
| `PermissionsManager.swift` | Accessibility + Screen Recording permission checks. Opens System Settings panes. |
| `N8nExporter.swift` | Workflow → n8n JSON converter. |
| `Config.swift` | **Gitignored.** Google OAuth client ID + secret. Must be filled manually from console.cloud.google.com. |
| `.gitignore` | Ignores: `.build/`, `Sessions/`, `Data/`, `Logs/`, `Config.swift` |

### Editor Models
| File | Purpose |
|---|---|
| `WorkflowEditorModels.swift` | Visual editor foundation: EditorGraph, EditorNode, EditorEdge, NodeConfigRegistry, GraphLayoutEngine, AIEditor, VersionManager, EditorGraphMigrator (WorkflowGraph → EditorGraph). ReactFlow-compatible JSON output. |
| `MirrorPipeline.swift` | Unified entry point that wires all 9 intelligence layers. Single `analyze()` call. |
| `MirrorTestHarness.swift` | 3 sample workflows + 10 automated tests. |

### UI (embedded in WKWebView)
| File | Purpose |
|---|---|
| `ui.html` | **Main app UI** (~750 lines). 3 tabs: Record, Editor, Settings button. Vanilla JS + SVG. No CDN, no frameworks. Recording/review/deploy views. SVG workflow editor with drag-to-create, pan/zoom, node connections, inspector panel. Bridge to Swift via `window.webkit.messageHandlers.mirrorBridge`. |
| `settings.html` | Settings window. API Keys tab (3 provider cards with Test/Clear/Use This). Permissions tab. Integrations tab (Google connect/disconnect/test). Workflows tab (list with Run Now/Pause/Delete). Activity tab. |

---

## Data Flow

### Recording → Analysis → Deploy (the main loop)

```
User clicks "Start Recording"
  → ui.html: bridge('recording.start')
  → FullWindowController: handleRecordingStart()
  → CaptureManager.startCapture()
    → EventTapManager.startCapture()  // CGEventTap, .listenOnly
    → ScreenRecorder.startCapture()   // ScreenCaptureKit, 1fps PNGs
  → Event counter timer starts (0.5s interval)
  → Escape key monitor starts

User works, then clicks "Stop & Analyze"
  → ui.html: bridge('recording.stop')
  → FullWindowController: handleRecordingStop()
  → CaptureManager.stopCapture() → session packaged → .mirrorpack zip
  → 0.3s delay → performAnalysis()

performAnalysis():
  → SessionPackager.loadEvents() from disk
  → SemanticActionExtractor.extract()    // events → actions
  → WorkflowIntentExtractor.extract()     // actions → artifacts + intent
  → WorkflowGraphBuilder.buildFullGraph() // actions+artifacts+intent → graph
  → EntityGraphBuilder.build()            // events+actions+artifacts → entities
  → BeliefStateEngine.update()            // everything → belief state
  → AnalysisPipeline.analyze()            // AI prompt with all context
    → Sends system prompt + timeline + extracted context to AI
    → Parses JSON response into Workflow struct
  → ui.html: window.mirror.showReviewState(workflow)
    → Populates review form (name, confidence, schedule, steps)
    → Populates editor graph (editNodes, editEdges)
    → Auto-switches to Editor view

User clicks "Deploy"
  → ui.html: bridge('workflow.deploy', {workflow:{name,trigger,steps}})
  → FullWindowController: handleDeploy()
    → WorkflowEngine.deploy()
      → Creates launchd plist at ~/Library/LaunchAgents/com.mirror.workflow.<uuid>.plist
      → Persists to ~/Mirror/Data/workflows.json
      → Loads into launchd
  → sendWorkflowList() → updates main UI + settings
```

### Editor (SVG-based, vanilla JS)

```
Node creation:
  → Drag from sidebar palette → creates editNodes[] entry → renderEditor()

Node rendering (renderEditor()):
  → SVG viewBox set for pan/zoom
  → <defs> with arrow markers + clipPaths per node
  → Edges rendered as bezier curves between node handles
  → Nodes rendered as <g transform="translate(x,y)"> with:
    - Body rect (240x90, rounded)
    - Header path (colored by category)
    - Label text (truncated to 20 chars)
    - Description text (truncated to 40 chars)
    - Confidence percentage
    - Cloud/desktop badge
    - Input handle (left, cx=0)
    - Output handle (right, cx=240)

Node inspection (renderInspector()):
  → Editable: label, description, action type (25 options), provider, execution type, confidence
  → Actions: duplicate, enable/disable, delete

Pan/zoom:
  → Canvas mousedown → panning mode → mouse move updates panOff ← renderEditor()
  → Scroll wheel → zoom *= 0.9/1.1

Connections:
  → Handle mousedown → connecting mode → mouseup on target node → creates edge
```

### Bridge Messages (JS → Swift)

All communication goes through `window.webkit.messageHandlers.mirrorBridge.postMessage({type: "..."})`.

| Message Type | Direction | Purpose |
|---|---|---|
| `recording.start` / `recording.stop` | JS→Swift | Recording control |
| `session.analyze` / `session.cancelAnalysis` | JS→Swift | Analysis control |
| `workflow.deploy` / `workflow.disable` / `workflow.enable` / `workflow.delete` / `workflow.list` / `workflow.runNow` | JS→Swift | Workflow management |
| `workflow.export.n8n` | JS→Swift | n8n export |
| `settings.open` / `settings.ready` / `settings.save` / `settings.saveAPIKey` / `settings.clearAPIKey` / `settings.testKey` | JS→Swift | Settings management |
| `permissions.check` / `permissions.openAccessibility` / `permissions.openScreenRecording` | JS→Swift | Permissions |
| `integrations.connectGoogle` / `integrations.disconnectGoogle` / `integrations.testGoogle` / `integrations.status` | JS→Swift | Google OAuth |
| `editor.ready` / `editor.runHistory` / `editor.workflowHealth` / `editor.runDetail` / `editor.workflowDetail` / `editor.save` / `editor.deploy` | JS→Swift | Editor data |
| `activity.list` | JS→Swift | Activity log |
| `clipboard.read` | JS→Swift | Clipboard paste fallback |

### Bridge Messages (Swift → JS)

Swift calls JS via `callJS(on: webView, "window.mirror.FUNCTION", args: [...])`.

| JS Function | Purpose |
|---|---|
| `showRecordingState()` / `updateEventCount(n)` / `updateDuration(d)` | Recording UI |
| `showAnalyzingState()` / `updateAnalysisProgress(pct, status)` | Analysis UI |
| `showReviewState(workflow)` | Review view + populate editor graph |
| `showDeployedState(info)` | Success banner |
| `showError(msg)` / `showPermissionError(a,s)` | Error display |
| `setWorkflowList(workflows)` | Render workflow list in main UI + settings |
| `setRunHistory(runs)` | Render run history in editor |
| `setWorkflowHealth(health)` | Health metrics |
| `setRunDetail(detail)` | Per-run node details |
| `showAutoGraph(steps)` | Populate editor from deployed workflow |
| `updateGoogleStatus(connected)` | Google connect status |
| `showGoogleTestResults(results)` | Integration test results |
| `showKeyTestResult(success)` | API key test |
| `setActivityList(entries)` | Activity log |
| `updatePermissions(status)` | Permission status |
| `loadSettings(settings)` | Populate settings form |
| `onSaved(ok)` / `onDeployed(ok, name)` | Editor save/deploy feedback |

---

## Key Architecture Patterns

### WKWebView Bridge
- `FullWindowController` implements `WKScriptMessageHandler`
- All windows (main, settings) register `self` as handler for `"mirrorBridge"`
- JS → Swift: `window.webkit.messageHandlers.mirrorBridge.postMessage(msg)`
- Swift → JS: `webView.evaluateJavaScript("window.mirror.fn(args)")`
- `deinit` MUST call `removeScriptMessageHandler(forName:)` to prevent SIGSEGV

### Singletons
- `CaptureManager.shared`
- `SessionPackager.shared`  
- `CredentialStore.shared`
- `RunHistoryStore.shared`
- `PendingApprovalStore.shared`

### State Management
- Workflows persisted to `~/Mirror/Data/workflows.json`
- Run history to `~/Mirror/Data/run_history.json`
- API keys + OAuth tokens in macOS Keychain
- UserDefaults for settings preferences
- Sessions saved to `~/Mirror/Sessions/<uuid>/`

### Security
- App Sandbox: disabled (required for CGEventTap, launchctl)
- API keys: macOS Keychain, `kSecAttrAccessibleWhenUnlocked`
- OAuth: PKCE flow, tokens never logged
- Config.swift: gitignored, contains client secrets
- run_script: command allowlist (curl, osascript, open, shortcuts)

---

## What Needs Manual Setup

1. **Google Cloud Console** → Create project "Mirror" → Enable Gmail, Sheets, Drive APIs → Create Desktop OAuth client → Paste into `Mirror/Config.swift`
2. **API Keys** → OpenRouter (openrouter.ai/keys), Anthropic, or OpenAI → Add in Settings
3. **Permissions** → macOS System Settings → Privacy → Accessibility + Screen Recording
4. **Code Signing** → `scripts/create-dev-cert.sh` for persistent identity (or ad-hoc fallback)

---

## Build & Run

```bash
cd /Users/jamesrabinowitz/Mirror
./build.sh        # builds, bundles, codesigns, installs to /Applications
open /Applications/Mirror.app
```

---

## Testing

```swift
// In code:
MirrorTestHarness.runAll()  // 10 tests, 3 sample workflows

// Manual:
// 1. Open Mirror → click Record → do a task → Stop & Analyze
// 2. Review steps → Deploy
// 3. Open Editor tab → inspect graph → edit nodes → Save
// 4. Settings → Workflows → Run Now
// 5. Settings → Integrations → Connect Google → Test
```

---

## Known Gaps (for next developer)

1. **No automated CI/CD** — no GitHub Actions, no test runner on push
2. **No unit tests as separate target** — MirrorTestHarness exists but isn't hooked into build
3. **Ad-hoc code signing** on fallback — Accessibility permission resets on rebuild
4. **Settings.html API Key UX** references old CSS classes (`.api-key-wrapper` etc.) that were partially removed
5. **Editor graph persistence** — the editor graph is in-memory only. Closing the window loses edits unless the user deploys
6. **No offline support** — Editor, AI analysis, and API connectors all require internet
7. **AI prompt size** — No token limit check before sending to API. Large recordings could be expensive
8. **Pricing/billing** — Not implemented. The app is currently free with user-provided API keys
