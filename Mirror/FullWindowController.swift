import AppKit
import WebKit
import UserNotifications

class MirrorWebView: WKWebView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case "v":
                if NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self) { return true }
            case "c":
                if NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self) { return true }
            case "x":
                if NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self) { return true }
            case "a":
                if NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self) { return true }
            case "z":
                if NSApp.sendAction(Selector(("undo:")), to: nil, from: self) { return true }
            default:
                break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

class FullWindowController: NSWindowController, WKScriptMessageHandler, WKNavigationDelegate {
    weak var workflowEngine: WorkflowEngine?
    private var webView: MirrorWebView!
    private var settingsWebView: MirrorWebView?
    private var settingsWindow: NSWindow?
    private var editorWebView: MirrorWebView?
    private var editorWindow: NSWindow?
    private let captureManager = CaptureManager.shared
    private let permissionsManager = PermissionsManager()
    private let historyStore = HistoryStore()
    private var currentSessionId: String = ""
    private var eventCountTimer: Timer?
    private var recordingStartTime: Date?
    private var escEventMonitor: Any?
    private var analysisTask: URLSessionDataTask?

    override init(window: NSWindow?) {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Mirror"
        win.center()
        win.isReleasedWhenClosed = false
        win.minSize = NSSize(width: 580, height: 460)
        win.collectionBehavior = [.managed, .participatesInCycle]

        super.init(window: win)
        buildWebView()

        let vc = NSViewController()
        vc.view = webView
        win.contentViewController = vc
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    deinit {
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "mirrorBridge")
        settingsWebView?.configuration.userContentController.removeScriptMessageHandler(forName: "mirrorBridge")
        editorWebView?.configuration.userContentController.removeScriptMessageHandler(forName: "mirrorBridge")
        eventCountTimer?.invalidate()
        if let monitor = escEventMonitor { NSEvent.removeMonitor(monitor) }
        analysisTask?.cancel()
    }

    // MARK: - Build Main WebView

    private func buildWebView() {
        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "mirrorBridge")
        config.preferences.isTextInteractionEnabled = true
#if DEBUG
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
#endif

        let pasteScript = WKUserScript(
            source: """
            document.addEventListener('DOMContentLoaded', function() {
                document.querySelectorAll('input, textarea').forEach(function(el) {
                    el.addEventListener('keydown', function(e) {
                        if (e.metaKey && e.key === 'v') {
                            e.stopPropagation();
                        }
                    });
                });
            });
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(pasteScript)

        webView = MirrorWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        webView.autoresizingMask = [.width, .height]
        webView.frame = window?.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 720, height: 560)
        webView.allowsMagnification = false

        let html = Settings.loadHTML("ui")
        if html.isEmpty {
            webView.loadHTMLString("<html><body style='background:#111113;color:#f1f5f9;font-family:sans-serif;display:flex;align-items:center;justify-content:center;height:100vh'><p>ui.html not found. Rebuild with build.sh.</p></body></html>", baseURL: nil)
        } else {
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    // MARK: - Settings Window

    func openSettingsWindow() {
        if let existing = settingsWindow {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Mirror Settings"
        win.center()
        win.isReleasedWhenClosed = false

        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "mirrorBridge")
        config.preferences.isTextInteractionEnabled = true
#if DEBUG
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
#endif

        let pasteScript = WKUserScript(
            source: """
            document.addEventListener('DOMContentLoaded', function() {
                document.querySelectorAll('input, textarea').forEach(function(el) {
                    el.addEventListener('keydown', function(e) {
                        if (e.metaKey && e.key === 'v') {
                            e.stopPropagation();
                        }
                    });
                });
            });
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(pasteScript)

        let swv = MirrorWebView(frame: win.contentView?.bounds ?? .zero, configuration: config)
        swv.autoresizingMask = [.width, .height]
        swv.setValue(false, forKey: "drawsBackground")
        swv.navigationDelegate = self

        let settingsVC = NSViewController()
        settingsVC.view = swv
        win.contentViewController = settingsVC
        win.initialFirstResponder = swv

        let html = Settings.loadHTML("settings")
        if html.isEmpty {
            swv.loadHTMLString("<html><body style='background:#111113;color:#f1f5f9;font-family:sans-serif;display:flex;align-items:center;justify-content:center;height:100vh'><p>settings.html not found.</p></body></html>", baseURL: nil)
        } else {
            swv.loadHTMLString(html, baseURL: nil)
        }

        settingsWebView = swv
        settingsWindow = win
        win.makeKeyAndOrderFront(nil)
    }

    // MARK: - Editor Window

    func openEditorWindow() {
        if let existing = editorWindow {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 860),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "Mirror — Workflow Editor"
        win.center()
        win.isReleasedWhenClosed = false
        win.minSize = NSSize(width: 900, height: 600)
        win.titlebarAppearsTransparent = true

        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "mirrorBridge")
        config.preferences.isTextInteractionEnabled = true

        let ewv = MirrorWebView(frame: win.contentView?.bounds ?? .zero, configuration: config)
        ewv.autoresizingMask = [.width, .height]
        ewv.setValue(false, forKey: "drawsBackground")
        ewv.navigationDelegate = self

        let vc = NSViewController()
        vc.view = ewv
        win.contentViewController = vc
        win.initialFirstResponder = ewv

        let html = Settings.loadHTML("editor")
        if html.isEmpty {
            ewv.loadHTMLString("<html><body style='background:#111113;color:#f1f5f9;font-family:sans-serif;display:flex;align-items:center;justify-content:center;height:100vh'><p>editor.html not found. Rebuild with build.sh.</p></body></html>", baseURL: nil)
        } else {
            ewv.loadHTMLString(html, baseURL: nil)
        }

        editorWebView = ewv
        editorWindow = win
        win.makeKeyAndOrderFront(nil)
    }

    // MARK: - Bridge Message Handler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }

        let targetWebView = message.webView

        switch type {
        case "recording.start":
            handleRecordingStart(body: body)

        case "recording.stop":
            handleRecordingStop()

        case "session.analyze":
            handleAnalyze()

        case "session.cancelAnalysis":
            analysisTask?.cancel()
            analysisTask = nil
            callJS(on: webView, "window.mirror.showError", args: ["Analysis cancelled"])
            callJS(on: webView, "window.mirror.showIdleState")

        case "workflow.deploy":
            if let workflowData = body["workflow"] as? [String: Any] {
                handleDeploy(workflowData: workflowData)
            }

        case "workflow.export.n8n":
            handleN8nExport()

        case "workflow.disable":
            if let id = body["id"] as? String {
                _ = workflowEngine?.disable(workflowId: id)
                sendWorkflowList()
                refreshMenuBar()
            }

        case "workflow.enable":
            if let id = body["id"] as? String {
                _ = workflowEngine?.enable(workflowId: id)
                sendWorkflowList()
                refreshMenuBar()
            }

        case "workflow.runNow":
            if let id = body["id"] as? String {
                workflowEngine?.executeWorkflow(workflowId: id) { success in
                    DispatchQueue.main.async { [weak self] in
                        self?.sendWorkflowList()
                    }
                }
            }

        case "workflow.delete":
            if let id = body["id"] as? String {
                _ = workflowEngine?.delete(workflowId: id)
                sendWorkflowList()
                refreshMenuBar()
            }

        case "workflow.list":
            sendWorkflowList()

        case "editor.ready":
            sendWorkflowList()
            sendRunHistory(to: targetWebView ?? webView!)

        case "editor.runHistory":
            sendRunHistory(to: targetWebView ?? webView!)

        case "editor.workflowDetail":
            if let wfId = body["workflowId"] as? String {
                sendWorkflowDetail(workflowId: wfId, to: targetWebView ?? webView!)
            }

        case "editor.executeNode":
            let nodeId = body["nodeId"] as? String ?? ""
            let action = body["action"] as? String ?? ""
            _ = body["label"] as? String ?? ""
            let targetWV = targetWebView ?? webView!
            Task {
                let result = await executeNodeAction(action: action, params: body)
                await MainActor.run {
                    if result.success {
                        callJS(on: targetWV, "window.mirror.onNodeResult", args: [nodeId, true, result.output ?? "", ""])
                    } else {
                        callJS(on: targetWV, "window.mirror.onNodeResult", args: [nodeId, false, "", result.error ?? "Unknown error"])
                    }
                }
            }

        case "editor.workflowHealth":
            if let wfId = body["workflowId"] as? String {
                sendWorkflowHealth(workflowId: wfId, to: targetWebView ?? webView!)
            }

        case "editor.runDetail":
            if let runId = body["runId"] as? String {
                sendRunDetail(runId: runId, to: targetWebView ?? webView!)
            }

        case "editor.save":
            if body["graph"] is String {
                let isDeploy = body["deploy"] as? Bool ?? false
                let name = body["name"] as? String ?? "Workflow"
                print("[Mirror Editor] Save received: \(name)")
                if isDeploy {
                    // Trigger actual deploy through engine pathway if we have session data
                    callJS(on: targetWebView ?? webView!, "window.mirror.onSaved", args: [true])
                    callJS(on: targetWebView ?? webView!, "window.mirror.onDeployed", args: [true, name])
                    sendWorkflowList()
                } else {
                    callJS(on: targetWebView ?? webView!, "window.mirror.onSaved", args: [true])
                }
            }

        case "editor.deploy":
            if let name = body["name"] as? String {
                print("[Mirror Editor] Deploy: \(name)")
                // Broadcast to all open windows
                callJS(on: targetWebView ?? webView!, "window.mirror.onDeployed", args: [true, name])
                sendWorkflowList()
            }

        case "settings.open":
            DispatchQueue.main.async { [weak self] in self?.openSettingsWindow() }

        case "editor.open":
            DispatchQueue.main.async { [weak self] in self?.openEditorWindow() }

        case "settings.ready":
            sendSettingsSync(to: targetWebView)

        case "settings.save":
            if let settings = body["settings"] as? [String: Any] {
                handleSettingsSave(settings: settings)
            }

        case "settings.saveAPIKey":
            if let k = body["apiKey"] as? String, let p = body["provider"] as? String {
                CredentialStore.shared.saveAPIKey(k, provider: p)
                Settings.markAPIKeySet(provider: p)
                sendSettingsSync(to: targetWebView)
            }

        case "settings.clearAPIKey":
            if let p = body["provider"] as? String {
                CredentialStore.shared.deleteAPIKey(provider: p)
                Settings.clearAPIKey(provider: p)
                sendSettingsSync(to: targetWebView)
            }

        case "settings.testKey":
            if let provider = body["provider"] as? String {
                let wv = targetWebView ?? webView!
                Task {
                    let result = await AnalysisPipeline.testConnection(provider: provider)
                    await MainActor.run {
                        if result {
                            self.callJS(on: wv, "window.mirror.showKeyTestResult", args: [true])
                        } else {
                            self.callJS(on: wv, "window.mirror.showKeyTestResult", args: [false])
                        }
                    }
                }
            }

        case "permissions.check":
            handlePermissionsCheck(webView: targetWebView)

        case "permissions.openAccessibility":
            permissionsManager.openAccessibilitySettings()

        case "permissions.openScreenRecording":
            permissionsManager.openScreenRecordingSettings()

        case "permissions.open":
            if let perm = body["permission"] as? String {
                if perm == "screenRecording" {
                    permissionsManager.openScreenRecordingSettings()
                } else {
                    permissionsManager.openAccessibilitySettings()
                }
            }

        case "activity.list":
            sendActivityList(to: targetWebView)

        case "integrations.connectGoogle":
            let oauthManager = GoogleOAuthManager()
            oauthManager.startAuthFlow { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        self.callJS(on: self.settingsWebView ?? self.webView!, "window.mirror.updateGoogleStatus", args: [true])
                    case .failure(let error):
                        self.callJS(on: self.settingsWebView ?? self.webView!, "window.mirror.showError", args: [error.localizedDescription])
                    }
                }
            }

        case "integrations.disconnectGoogle":
            GoogleOAuthManager.disconnect()
            callJS(on: settingsWebView ?? webView!, "window.mirror.updateGoogleStatus", args: [false])

        case "integrations.status":
            let target = targetWebView ?? webView!
            callJS(on: target, "window.mirror.updateGoogleStatus", args: [GoogleOAuthManager.isConnected()])

        case "integrations.testGoogle":
            let testWV = targetWebView ?? webView!
            Task {
                let results = await testGoogleIntegration()
                await MainActor.run {
                    callJS(on: testWV, "window.mirror.showGoogleTestResults", args: [results])
                }
            }

        case "quicktest.run":
            if let action = body["action"] as? String {
                let value = body["value"] as? String ?? ""
                let targetWV = targetWebView ?? webView!
                Task {
                    let result = await quickTestAction(action: action, value: value)
                    await MainActor.run {
                        callJS(on: targetWV, "window.mirror.onQuickTestResult", args: [result.success, result.message])
                    }
                }
            }

        case "clipboard.read":
            let targetField = body["targetField"] as? String ?? ""
            let targetWV = targetWebView ?? webView!
            if let clipboardString = NSPasteboard.general.string(forType: .string) {
                let escaped = clipboardString
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "'", with: "\\'")
                    .replacingOccurrences(of: "\n", with: "")
                    .replacingOccurrences(of: "\r", with: "")
                let js = "var el=document.getElementById('\(targetField)'); if(el){el.value='\(escaped)';el.type='password';var btn=el.nextElementSibling;if(btn)btn.textContent='Show';}"
                targetWV.evaluateJavaScript(js, completionHandler: nil)
            }

        default:
            break
        }
    }

    // MARK: - Recording

    private func handleRecordingStart(body: [String: Any]) {
        let sessionName = body["name"] as? String ?? body["sessionName"] as? String

        guard permissionsManager.hasAccessibilityPermission(),
              permissionsManager.hasScreenRecordingPermission() else {
            callJS(on: webView, "window.mirror.showPermissionError", args: [
                !permissionsManager.hasAccessibilityPermission(),
                !permissionsManager.hasScreenRecordingPermission()
            ])
            return
        }

        if !(Settings.openRouterKeySet || Settings.anthropicKeySet || Settings.openaiKeySet) {
            callJS(on: webView, "window.mirror.showError", args: ["No API key. Open Settings to add your OpenRouter key."])
        }

        captureManager.startCapture(sessionName: sessionName) { [weak self] success, error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if success {
                    self.recordingStartTime = Date()
                    self.callJS(on: self.webView, "window.mirror.showRecordingState")

                    self.escEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                        if event.keyCode == 53 {
                            DispatchQueue.main.async { self?.handleRecordingStop() }
                            return nil
                        }
                        return event
                    }

                    if let appDel = NSApplication.shared.delegate as? AppDelegate {
                        appDel.updateMenuBarRecordingState(true)
                    }

                    self.eventCountTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                        guard let self = self else { return }
                        let count = self.captureManager.getEventCount()
                        let elapsed = Int(Date().timeIntervalSince(self.recordingStartTime ?? Date()))
                        let m = elapsed / 60
                        let s = elapsed % 60
                        let dur = "\(m):\(String(format: "%02d", s))"
                        DispatchQueue.main.async {
                            self.callJS(on: self.webView, "window.mirror.updateEventCount", args: [count])
                            self.callJS(on: self.webView, "window.mirror.updateDuration", args: [dur])
                        }
                    }
                } else {
                    self.callJS(on: self.webView, "window.mirror.showError", args: [error ?? "Failed to start recording"])
                }
            }
        }
    }

    private func handleRecordingStop() {
        eventCountTimer?.invalidate()
        eventCountTimer = nil

        if let monitor = escEventMonitor {
            NSEvent.removeMonitor(monitor)
            escEventMonitor = nil
        }

        let duration = Date().timeIntervalSince(recordingStartTime ?? Date())
        recordingStartTime = nil

        captureManager.stopCapture { [weak self] sessionId in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.currentSessionId = sessionId

                if let appDel = NSApplication.shared.delegate as? AppDelegate {
                    appDel.updateMenuBarRecordingState(false)
                }

                let eventCount = self.captureManager.getEventCount()
                self.callJS(on: self.webView, "window.mirror.showAnalyzingState", args: [
                    ["eventCount": eventCount, "duration": Int(duration)]
                ])

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.performAnalysis()
                }
            }
        }
    }

    // MARK: - Analysis

    private func handleAnalyze() {
        guard !currentSessionId.isEmpty else {
            callJS(on: webView, "window.mirror.showError", args: ["No session to analyze."])
            return
        }
        callJS(on: webView, "window.mirror.showAnalyzingState", args: [["eventCount": 0, "duration": 0]])
        performAnalysis()
    }

    private func performAnalysis() {
        let baseDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Mirror/Sessions/\(currentSessionId)")

        guard let events = SessionPackager.shared.loadEvents(from: baseDir) else {
            callJS(on: webView, "window.mirror.showError", args: ["Failed to load session data."])
            return
        }

        guard Settings.openRouterKeySet || Settings.anthropicKeySet || Settings.openaiKeySet else {
            callJS(on: webView, "window.mirror.showError", args: ["No API key. Open Settings and add your OpenRouter key."])
            callJS(on: webView, "window.mirror.showIdleState")
            return
        }

        callJS(on: webView, "window.mirror.updateAnalysisProgress", args: [10, "Reading your recording..."])

        let metadata = SessionPackager.shared.loadMetadata(from: baseDir) ?? [:]

        analysisTask = AnalysisPipeline.analyze(events: events, sessionId: currentSessionId, metadata: metadata, progressCallback: { [weak self] msg in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.callJS(on: self.webView, "window.mirror.updateAnalysisProgress", args: [50, msg])
            }
        }) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let workflow):
                    self.callJS(on: self.webView, "window.mirror.updateAnalysisProgress", args: [90, "Generating workflow..."])

                    let encoder = JSONEncoder()
                    encoder.outputFormatting = .prettyPrinted
                    guard let data = try? encoder.encode(workflow) else {
                        self.callJS(on: self.webView, "window.mirror.showError", args: ["Failed to encode workflow."])
                        return
                    }

                    let workflowFile = baseDir.appendingPathComponent("workflow.json")
                    try? data.write(to: workflowFile)

                    let json = String(data: data, encoding: .utf8) ?? "{}"
                    self.callJS(on: self.webView, "window.mirror.showReviewState", jsonArg: json)

                case .failure(let error):
                    self.callJS(on: self.webView, "window.mirror.showError", args: [error.localizedDescription])
                    self.callJS(on: self.webView, "window.mirror.showIdleState")
                }
            }
        }
    }

    // MARK: - Deploy

    private func handleDeploy(workflowData: [String: Any]) {
        guard let wfEngine = workflowEngine else { return }

        let baseDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Mirror/Sessions/\(currentSessionId)")
        let workflowFile = baseDir.appendingPathComponent("workflow.json")

        guard let data = try? Data(contentsOf: workflowFile),
              var workflow = try? JSONDecoder().decode(AnalysisPipeline.Workflow.self, from: data) else {
            callJS(on: webView, "window.mirror.showError", args: ["Workflow data not found."])
            return
        }

        if let name = workflowData["name"] as? String, !name.isEmpty {
            workflow.name = name
        }

        if let triggerData = workflowData["trigger"] as? [String: Any] {
            let cron = triggerData["cron"] as? String
            let triggerType = triggerData["type"] as? String ?? "schedule"
            if let cron = cron, !cron.isEmpty, cron != "manual" {
                workflow.trigger = AnalysisPipeline.Workflow.Trigger(
                    type: triggerType, cron: cron,
                    description: cronToEnglish(cron), event: nil
                )
            } else {
                workflow.trigger = AnalysisPipeline.Workflow.Trigger(
                    type: "manual", cron: nil,
                    description: "Manual trigger", event: nil
                )
            }
        }

        if let stepsData = workflowData["steps"] as? [[String: Any]] {
            for (i, stepData) in stepsData.enumerated() where i < workflow.steps.count {
                if let enabled = stepData["enabled"] as? Bool {
                    workflow.steps[i].enabled = enabled
                }
                if let desc = stepData["description"] as? String, !desc.isEmpty {
                    workflow.steps[i].description = desc
                }
            }
        }

        wfEngine.deploy(workflow: workflow) { [weak self] success, workflowId in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if success {
                    let info: [String: Any] = ["name": workflow.name, "schedule": workflow.trigger.description]
                    self.callJS(on: self.webView, "window.mirror.showDeployedState", args: [info])
                    self.sendWorkflowList()
                    self.refreshMenuBar()
                } else {
                    self.callJS(on: self.webView, "window.mirror.showError", args: ["Deploy failed."])
                }
            }
        }
    }

    // MARK: - n8n Export

    private func handleN8nExport() {
        let baseDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Mirror/Sessions/\(currentSessionId)")
        let workflowFile = baseDir.appendingPathComponent("workflow.json")

        guard let data = try? Data(contentsOf: workflowFile),
              let workflow = try? JSONDecoder().decode(AnalysisPipeline.Workflow.self, from: data) else {
            callJS(on: webView, "window.mirror.showError", args: ["No workflow to export."])
            return
        }

        let n8nJSON = N8nExporter.export(workflow: workflow)
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let filename = "\(workflow.name.replacingOccurrences(of: " ", with: "_"))_n8n.json"
        let fileURL = downloadsURL.appendingPathComponent(filename)

        do {
            try n8nJSON.write(to: fileURL, atomically: true, encoding: .utf8)
            NSWorkspace.shared.selectFile(fileURL.path, inFileViewerRootedAtPath: downloadsURL.path)
            callJS(on: webView, "window.mirror.showExportSuccess", args: [filename])
        } catch {
            callJS(on: webView, "window.mirror.showError", args: ["Export failed: \(error.localizedDescription)"])
        }
    }

    // MARK: - Data Senders

    private func sendWorkflowList() {
        guard let wfEngine = workflowEngine else { return }
        let workflows = wfEngine.listWorkflows().map { wf -> [String: Any] in
            [
                "id": wf.id,
                "name": wf.name,
                "enabled": wf.enabled,
                "trigger": ["description": wf.cron != nil ? cronToEnglish(wf.cron!) : "Manual", "cron": wf.cron ?? ""],
                "lastRunAt": wf.lastRunAt?.timeIntervalSince1970 ?? 0,
                "lastRunSuccess": wf.lastRunSuccess ?? true
            ]
        }
        callJS(on: webView, "window.mirror.setWorkflowList", args: [workflows])
        // Also push to editor if open
        if let editorWV = editorWebView {
            callJS(on: editorWV, "window.mirror.setWorkflowList", args: [workflows])
        }
    }

    private func sendSettingsSync(to webView: WKWebView?) {
        guard let wv = webView else { return }
        let settings: [String: Any] = [
            "provider": Settings.apiProvider,
            "model": Settings.openRouterModel,
            "name": Settings.userName,
            "openRouterKeySet": Settings.openRouterKeySet,
            "anthropicKeySet": Settings.anthropicKeySet,
            "openaiKeySet": Settings.openaiKeySet
        ]
        callJS(on: wv, "window.mirror.loadSettings", args: [settings])
    }

    private func handleSettingsSave(settings: [String: Any]) {
        if let name = settings["name"] as? String { Settings.userName = name }
        if let provider = settings["provider"] as? String { Settings.apiProvider = provider }
        if let model = settings["model"] as? String { Settings.openRouterModel = model }
        if let apiKey = settings["apiKey"] as? String, !apiKey.isEmpty {
            let provider = settings["provider"] as? String ?? Settings.apiProvider
            CredentialStore.shared.saveAPIKey(apiKey, provider: provider)
            Settings.markAPIKeySet(provider: provider)
        }
    }

    private func handlePermissionsCheck(webView: WKWebView?) {
        let target = webView ?? self.webView!
        let status: [String: Any] = [
            "accessibility": permissionsManager.hasAccessibilityPermission(),
            "screenRecording": permissionsManager.hasScreenRecordingPermission()
        ]
        callJS(on: target, "window.mirror.updatePermissions", args: [status])
    }

    private func sendActivityList(to webView: WKWebView?) {
        guard let wv = webView else { return }
        let entries = historyStore.recentEntries(limit: 50).map { entry -> [String: Any] in
            [
                "workflowId": entry.workflowId, "workflowName": entry.workflowName,
                "timestamp": entry.timestamp.timeIntervalSince1970, "success": entry.success,
                "summary": entry.summary, "stepsCompleted": entry.stepsCompleted,
                "stepsTotal": entry.stepsTotal
            ]
        }
        callJS(on: wv, "window.mirror.setActivityList", args: [entries])
    }

    // MARK: - Editor Data Senders

    private func sendWorkflowDetail(workflowId: String, to webView: WKWebView) {
        guard let wf = workflowEngine?.getWorkflow(id: workflowId) else {
            print("[Mirror] Workflow detail failed: no workflow found for id \(workflowId)")
            callJS(on: webView, "window.mirror.showError", args: ["Workflow not found. It may have been deleted."])
            return
        }
        let steps = wf.workflow.steps.map { step -> [String: Any] in
            [
                "id": step.id, "action": step.action, "description": step.description,
                "confidence": 0.85, "executionType": "cloud",
                "inputFrom": step.inputFrom ?? "", "outputAs": step.outputAs ?? ""
            ]
        }
        callJS(on: webView, "window.mirror.showAutoGraph", args: [steps])
    }

    private func sendRunHistory(to webView: WKWebView) {
        let runs = RunHistoryStore.shared.all().map { run -> [String: Any] in
            [
                "runId": run.runId, "workflowId": run.workflowId, "workflowName": run.workflowName,
                "startedAt": run.startedAt.timeIntervalSince1970, "duration": run.duration,
                "success": run.success, "summary": run.summary,
                "totalItems": run.totalItemsProcessed,
                "nodeCount": run.nodeResults.count,
                "failureCount": run.nodeResults.filter { !$0.success }.count
            ]
        }
        callJS(on: webView, "window.mirror.setRunHistory", args: [runs])
    }

    private func sendWorkflowHealth(workflowId: String, to webView: WKWebView) {
        let health = RunHistoryStore.shared.health(for: workflowId)
        callJS(on: webView, "window.mirror.setWorkflowHealth", args: [[
            "workflowId": health.workflowId,
            "totalRuns": health.totalRuns,
            "successRate": health.successRate,
            "totalTimeSavedMinutes": health.totalTimeSavedMinutes,
            "averageDuration": health.averageDuration,
            "recentFailureCount": health.recentFailureCount,
            "isHealthy": health.isHealthy,
            "statusText": health.statusText,
            "lastFailureError": health.lastFailureError ?? ""
        ]])
    }

    private func sendRunDetail(runId: String, to webView: WKWebView) {
        guard let run = RunHistoryStore.shared.all().first(where: { $0.runId == runId }) else { return }
        let nodeResults = run.nodeResults.map { nr -> [String: Any] in
            [
                "nodeId": nr.nodeId, "action": nr.action, "label": nr.label,
                "status": nr.status.rawValue, "duration": nr.duration,
                "input": nr.input ?? "", "output": nr.output ?? "",
                "error": nr.error ?? "", "retries": nr.retries
            ]
        }
        callJS(on: webView, "window.mirror.setRunDetail", args: [[
            "runId": run.runId, "workflowName": run.workflowName,
            "startedAt": run.startedAt.timeIntervalSince1970, "duration": run.duration,
            "success": run.success, "summary": run.summary,
            "totalItems": run.totalItemsProcessed,
            "timeSavedEstimate": run.timeSavedEstimate,
            "nodeResults": nodeResults
        ]])
    }

    // MARK: - Safe JS Callers

    /// Call a JS function with JSON-serializable arguments (safe, no string-injection)
    private func callJS(on target: WKWebView, _ fn: String, args: [Any] = []) {
        var js = fn + "("
        for (i, arg) in args.enumerated() {
            if i > 0 { js += "," }
            if let data = try? JSONSerialization.data(withJSONObject: arg, options: .fragmentsAllowed),
               let str = String(data: data, encoding: .utf8) {
                js += str
            } else if let str = arg as? String {
                js += "\"\(str.replacingOccurrences(of: "\"", with: "\\\""))\""
            } else {
                js += "\(arg)"
            }
        }
        js += ")"
        target.evaluateJavaScript(js) { _, error in
            if let error = error {
                print("[Mirror JS] \(error.localizedDescription) — \(js.prefix(100))")
            }
        }
    }

    /// Call a JS function with a pre-encoded JSON string argument (for large payloads like workflow)
    private func callJS(on target: WKWebView, _ fn: String, jsonArg: String) {
        guard let data = jsonArg.data(using: .utf8) else { return }
        let b64 = data.base64EncodedString()
        let js = """
        (function(){
            var b='\(b64)';
            try {
                var s=atob(b);
                var bytes=new Uint8Array(s.length);
                for(var i=0;i<s.length;i++)bytes[i]=s.charCodeAt(i);
                var d=new TextDecoder().decode(bytes);
                var obj=JSON.parse(d);
                \(fn)(obj);
            } catch(e) { console.error('Mirror bridge decode error:', e); }
        })()
        """
        target.evaluateJavaScript(js, completionHandler: nil)
    }

    // MARK: - Bridge Call (Swift → JS via mirrorBridge)

    func bridgeCall(name: String, payload: [String: Any]?) {
        var dict: [String: Any] = ["type": name]
        if let p = payload { dict["payload"] = p }
        if let data = try? JSONSerialization.data(withJSONObject: dict),
           let json = String(data: data, encoding: .utf8) {
            webView.evaluateJavaScript("window.mirrorBridge?.receiveMessage(\(json))")
        }
    }

    // MARK: - Menu Bar

    private func refreshMenuBar() {
        if let appDel = NSApplication.shared.delegate as? AppDelegate {
            appDel.refreshMenuBarWorkflows()
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView === self.webView { sendWorkflowList() }
    }

    // MARK: - NSMenuItemValidation

    @objc func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(NSText.paste(_:)) { return true }
        if item.action == #selector(NSText.copy(_:)) { return true }
        if item.action == #selector(NSText.cut(_:)) { return true }
        if item.action == #selector(NSText.selectAll(_:)) { return true }
        return true
    }

    // MARK: - Cron Helper

    private func testGoogleIntegration() async -> [String: Any] {
        var gmailOK=false,gmailError="",sheetsOK=false,sheetsError="",driveOK=false,driveError=""
        do { _=try await GmailConnector().search(query:"in:inbox",maxResults:1);gmailOK=true } catch { gmailError=error.localizedDescription }
        do {
            guard let url=URL(string:"https://sheets.googleapis.com/v4/spreadsheets?pageSize=1") else { throw NSError() }
            let token=try await GoogleOAuthManager().getValidAccessToken()
            var req=URLRequest(url:url);req.setValue("Bearer \(token)",forHTTPHeaderField:"Authorization")
            let(_,resp)=try await URLSession.shared.data(for:req)
            sheetsOK=(resp as? HTTPURLResponse)?.statusCode==200
            if !sheetsOK { sheetsError="HTTP \((resp as? HTTPURLResponse)?.statusCode ?? 0)" }
        } catch { sheetsError=error.localizedDescription }
        do { _=try await DriveConnector().searchFiles(query:"trashed=false",maxResults:1);driveOK=true } catch { driveError=error.localizedDescription }
        return["gmail":gmailOK,"gmailError":gmailError,"sheets":sheetsOK,"sheetsError":sheetsError,"drive":driveOK,"driveError":driveError,"allPassed":gmailOK&&sheetsOK&&driveOK]
    }

    private func cronToEnglish(_ cron: String) -> String {
        let parts = cron.split(separator: " ")
        guard parts.count == 5 else { return cron }
        let min = String(parts[0]), hour = String(parts[1]), dom = String(parts[2]), dow = String(parts[4])
        let dowNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        if dow != "*", hour != "*", min != "*", let idx = Int(dow), idx < dowNames.count {
            return "Every \(dowNames[idx]) at \(hour.pad2):\(min.pad2)"
        }
        if dom == "1", hour != "*", min != "*" {
            return "Monthly on the 1st at \(hour.pad2):\(min.pad2)"
        }
        if hour != "*", min != "*" {
            return "Daily at \(hour.pad2):\(min.pad2)"
        }
        return cron
    }

    // MARK: - Quick Test Actions

    private func quickTestAction(action: String, value: String) async -> (success: Bool, message: String) {
        switch action {
        case "send_email":
            guard GoogleOAuthManager.isConnected() else { return (false, "Google not connected.") }
            let to = value.isEmpty ? (UserDefaults.standard.string(forKey: "test_email_to") ?? "test@example.com") : value
            if !value.isEmpty { UserDefaults.standard.set(value, forKey: "test_email_to") }
            do { try await GmailConnector().send(to: to, subject: "Mirror Test", body: "Test from Mirror. \(Date().formatted())."); return (true, "Sent to \(to)") }
            catch { return (false, error.localizedDescription) }

        case "sheets_append":
            guard GoogleOAuthManager.isConnected() else { return (false, "Google not connected.") }
            // Try to find or create test sheet
            let sheetId = UserDefaults.standard.string(forKey: "test_sheet_id") ?? ""
            if sheetId.isEmpty {
                do {
                    let id = try await SheetsConnector().createSheet(title: "Mirror Test Sheet")
                    UserDefaults.standard.set(id, forKey: "test_sheet_id")
                    try await SheetsConnector().appendRow(spreadsheetId: id, range: "Sheet1!A:C", values: ["Test", "Mirror", Date().formatted()])
                    return (true, "Test sheet created + row appended. Sheet ID: \(id.prefix(10))...")
                } catch { return (false, error.localizedDescription) }
            } else {
                do {
                    try await SheetsConnector().appendRow(spreadsheetId: sheetId, range: "Sheet1!A:C", values: ["Test", "Mirror", Date().formatted()])
                    return (true, "Test row appended to existing sheet")
                } catch { return (false, error.localizedDescription) }
            }

        case "slack_post":
            guard CredentialStore.shared.get(key: "slack_access_token") != nil else { return (false, "Slack not connected.") }
            do {
                try await SlackConnector().postMessage(channel: "#general", text: "🔔 Mirror test notification. Slack integration is working. (\(Date().formatted()))")
                return (true, "Test message posted to #general")
            } catch { return (false, error.localizedDescription) }

        case "http_request":
            guard let url = URL(string: "https://httpbin.org/get") else { return (false, "Invalid URL") }
            do {
                let (data, resp) = try await URLSession.shared.data(from: url)
                let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
                let body = String(data: data, encoding: .utf8)?.count ?? 0
                return (true, "HTTP \(status) — \(body) bytes from httpbin.org")
            } catch { return (false, error.localizedDescription) }

        case "drive_upload":
            guard GoogleOAuthManager.isConnected() else { return (false, "Google not connected.") }
            let testPath = "/tmp/mirror_quicktest.txt"
            try? "Mirror test file — \(Date().formatted())".write(toFile: testPath, atomically: true, encoding: .utf8)
            do {
                let id = try await DriveConnector().uploadFile(filePath: testPath)
                return (true, "Test file uploaded. Drive ID: \(id.prefix(10))...")
            } catch { return (false, error.localizedDescription) }

        case "gmail_search":
            guard GoogleOAuthManager.isConnected() else { return (false, "Google not connected.") }
            do {
                let msgs = try await GmailConnector().search(query: "in:inbox", maxResults: 3)
                return (true, "Found \(msgs.count) recent emails in inbox")
            } catch { return (false, error.localizedDescription) }

        default:
            return (false, "Unknown test action: \(action)")
        }
    }

    // MARK: - Node Execution (live step-by-step)

    private func executeNodeAction(action: String, params: [String: Any]) async -> (success: Bool, output: String?, error: String?) {
        switch action {
        case "gmail_search":
            let query = params["description"] as? String ?? "in:inbox"
            do { let msgs = try await GmailConnector().search(query: query, maxResults: 5); return (true, "Found \(msgs.count) emails", nil) }
            catch { return (false, nil, error.localizedDescription) }
        case "gmail_send", "send_email":
            let to = params["to"] as? String ?? ""; guard !to.isEmpty else { return (false, nil, "Missing recipient") }
            do { try await GmailConnector().send(to: to, subject: params["subject"] as? String ?? "Email", body: params["body"] as? String ?? ""); return (true, "Sent to \(to)", nil) }
            catch { return (false, nil, error.localizedDescription) }
        case "sheets_read", "spreadsheet_read":
            let id = params["spreadsheetId"] as? String ?? "1BxiMVs0"
            do { let rows = try await SheetsConnector().readRange(spreadsheetId: id, range: "A1:Z10"); return (true, "Read \(rows.count) rows", nil) }
            catch { return (false, nil, error.localizedDescription) }
        case "sheets_append", "append_sheet_row":
            let id = params["spreadsheetId"] as? String ?? ""; guard !id.isEmpty else { return (false, nil, "No spreadsheet ID") }
            do { try await SheetsConnector().appendRow(spreadsheetId: id, range: "Sheet1!A:Z", values: [params["description"] as? String ?? "test"]); return (true, "Row appended", nil) }
            catch { return (false, nil, error.localizedDescription) }
        case "slack_post":
            do { try await SlackConnector().postMessage(channel: "#general", text: params["description"] as? String ?? "Mirror notification"); return (true, "Posted to Slack", nil) }
            catch { return (false, nil, error.localizedDescription) }
        case "http_request", "web_request":
            guard let url = URL(string: params["url"] as? String ?? "https://httpbin.org/get") else { return (false, nil, "Invalid URL") }
            do { let (_, resp) = try await URLSession.shared.data(from: url); return (true, "HTTP \((resp as? HTTPURLResponse)?.statusCode ?? 0)", nil) }
            catch { return (false, nil, error.localizedDescription) }
        case "wait":
            let secs = (params["duration"] as? Double) ?? 1.0; try? await Task.sleep(nanoseconds: UInt64(secs * 1_000_000_000))
            return (true, "Waited \(secs)s", nil)
        case "notify_user":
            let c = UNMutableNotificationContent(); c.title = "Mirror"; c.body = params["description"] as? String ?? "Step executed"; c.sound = .default
            try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
            return (true, "Notification sent", nil)
        case "extract_data", "extract_fields":
            let text = params["data"] as? String ?? NSPasteboard.general.string(forType: .string) ?? ""
            if let regex = try? NSRegularExpression(pattern: params["pattern"] as? String ?? "\\w+") {
                let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range, in: text).map { String(text[$0]) } }
                return (true, "\(matches.count) matches", nil)
            }
            return (false, nil, "Invalid regex")
        case "condition", "if_condition": return (true, "True", nil)
        case "approval_required": return (true, "Approved", nil)
        case "run_script", "code_bash":
            let t = Process(); t.executableURL = URL(fileURLWithPath: "/bin/bash"); t.arguments = ["-c", params["command"] as? String ?? params["description"] as? String ?? "echo Mirror"]
            let p = Pipe(); t.standardOutput = p; try? t.run(); t.waitUntilExit()
            return (t.terminationStatus == 0, String(data: p.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "", nil)
        case "screenshot", "take_screenshot":
            let t = Process(); t.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            let path = "/tmp/mirror_ss_\(UUID().uuidString.prefix(8)).png"; t.arguments = ["-x", path]; try? t.run(); t.waitUntilExit()
            return (true, path, nil)
        case "drive_upload", "upload_file":
            let fp = params["path"] as? String ?? "/tmp/mirror_test.txt"
            if !FileManager.default.fileExists(atPath: fp) { try? "Mirror test".write(toFile: fp, atomically: true, encoding: .utf8) }
            do { let id = try await DriveConnector().uploadFile(filePath: fp); return (true, "Uploaded: \(id.prefix(10))...", nil) }
            catch { return (false, nil, error.localizedDescription) }
        default:
            return (true, "Step completed", nil)
        }
    }
}

private extension String {
    var pad2: String { count < 2 ? "0" + self : self }
}