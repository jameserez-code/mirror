import AppKit
import WebKit

class FullWindowController: NSWindowController, WKScriptMessageHandler, WKNavigationDelegate {
    weak var workflowEngine: WorkflowEngine?
    private var webView: WKWebView!
    private var settingsWebView: WKWebView?
    private var settingsWindow: NSWindow?
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

    // MARK: - Build Main WebView

    private func buildWebView() {
        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "mirrorBridge")
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        webView = WKWebView(frame: .zero, configuration: config)
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
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let swv = WKWebView(frame: win.contentView?.bounds ?? .zero, configuration: config)
        swv.autoresizingMask = [.width, .height]
        swv.setValue(false, forKey: "drawsBackground")
        swv.navigationDelegate = self

        let settingsVC = NSViewController()
        settingsVC.view = swv
        win.contentViewController = settingsVC

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

        case "workflow.delete":
            if let id = body["id"] as? String {
                _ = workflowEngine?.delete(workflowId: id)
                sendWorkflowList()
                refreshMenuBar()
            }

        case "workflow.list":
            sendWorkflowList()

        case "settings.open":
            DispatchQueue.main.async { [weak self] in self?.openSettingsWindow() }

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

        analysisTask = AnalysisPipeline.analyze(events: events, sessionId: currentSessionId, metadata: metadata) { [weak self] result in
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
        let safe = jsonArg.replacingOccurrences(of: "\\", with: "\\\\")
                         .replacingOccurrences(of: "'", with: "\\'")
                         .replacingOccurrences(of: "\n", with: "\\n")
                         .replacingOccurrences(of: "\r", with: "\\r")
        let js = "\(fn)(JSON.parse('\(safe)'))"
        target.evaluateJavaScript(js) { _, error in
            if let error = error {
                print("[Mirror JS] \(error.localizedDescription) — JSON parse failed, retrying with base64")
                self.callJSBase64(on: target, fn, json: jsonArg)
            }
        }
    }

    /// Fallback: pass JSON as base64
    private func callJSBase64(on target: WKWebView, _ fn: String, json: String) {
        guard let data = json.data(using: .utf8) else { return }
        let b64 = data.base64EncodedString()
        // Decode base64 to UTF-8 bytes via a two-step process in JS
        let js = """
        (function(){
            var b='\(b64)';
            var s=atob(b);
            var bytes=new Uint8Array(s.length);
            for(var i=0;i<s.length;i++)bytes[i]=s.charCodeAt(i);
            var d=new TextDecoder().decode(bytes);
            \(fn)(JSON.parse(d));
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

    // MARK: - Cron Helper

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
}

private extension String {
    var pad2: String { count < 2 ? "0" + self : self }
}