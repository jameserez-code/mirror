import Foundation
import AppKit
import CoreGraphics
import UserNotifications

class WorkflowEngine {
    private var workflows: [String: DeployedWorkflow] = [:]
    private let historyStore = HistoryStore()

    struct DeployedWorkflow: Codable {
        let id: String
        let name: String
        let workflow: AnalysisPipeline.Workflow
        let cron: String?
        let plistPath: String
        var enabled: Bool
        let createdAt: Date
        var lastRunAt: Date?
        var lastRunSuccess: Bool?
    }

    struct RunLogEntry: Codable {
        let workflowId: String
        let workflowName: String
        let timestamp: Date
        let success: Bool
        let summary: String
        let stepsCompleted: Int
        let stepsTotal: Int
    }

    // MARK: - CRUD

    func deploy(workflow: AnalysisPipeline.Workflow, completion: @escaping (Bool, String) -> Void) {
        let id = UUID().uuidString
        let plistPath = createLaunchdPlist(workflowId: id, workflow: workflow)

        let deployed = DeployedWorkflow(
            id: id,
            name: workflow.name,
            workflow: workflow,
            cron: workflow.trigger.cron,
            plistPath: plistPath,
            enabled: true,
            createdAt: Date(),
            lastRunAt: nil,
            lastRunSuccess: nil
        )

        workflows[id] = deployed
        loadLaunchdJob(plistPath: plistPath)
        persistWorkflowStates()

        completion(true, id)
    }

    func disable(workflowId: String) -> Bool {
        guard var wf = workflows[workflowId] else { return false }
        wf.enabled = false
        workflows[workflowId] = wf
        unloadLaunchdJob(plistPath: wf.plistPath)
        persistWorkflowStates()
        return true
    }

    func enable(workflowId: String) -> Bool {
        guard var wf = workflows[workflowId] else { return false }
        wf.enabled = true
        workflows[workflowId] = wf
        loadLaunchdJob(plistPath: wf.plistPath)
        persistWorkflowStates()
        return true
    }

    func delete(workflowId: String) -> Bool {
        guard let wf = workflows[workflowId] else { return false }
        unloadLaunchdJob(plistPath: wf.plistPath)
        try? FileManager.default.removeItem(atPath: wf.plistPath)
        // Clean up log directory
        let logDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Mirror/Logs/\(workflowId)")
        try? FileManager.default.removeItem(at: logDir)
        workflows.removeValue(forKey: workflowId)
        persistWorkflowStates()
        return true
    }

    func listWorkflows() -> [DeployedWorkflow] {
        return Array(workflows.values).sorted { $0.createdAt > $1.createdAt }
    }

    func getWorkflow(id: String) -> DeployedWorkflow? {
        return workflows[id]
    }

    // MARK: - Execution

    func executeWorkflow(workflowId: String) {
        executeWorkflow(workflowId: workflowId, completion: nil)
    }

    func executeWorkflow(workflowId: String, completion: ((Bool) -> Void)?) {
        guard let wf = workflows[workflowId], wf.enabled else {
            completion?(false)
            return
        }

        stepOutputs = [:]
        let totalSteps = wf.workflow.steps.count
        var completed = 0
        let runId = UUID().uuidString

        // Execute steps sequentially (V1 — simple sequential execution)
        Task {
            var success = true
            for step in wf.workflow.steps where step.enabled {
                let result = await executeStep(step, workflowId: workflowId, runId: runId)
                if result { completed += 1 } else { success = false }
            }

            let finalSuccess = success
            let finalCompleted = completed
            await MainActor.run {
                let summary = finalSuccess ? "All \(finalCompleted) steps completed successfully" : "\(finalCompleted)/\(totalSteps) steps completed — some steps failed"
                let entry = RunLogEntry(
                    workflowId: workflowId,
                    workflowName: wf.name,
                    timestamp: Date(),
                    success: finalSuccess,
                    summary: summary,
                    stepsCompleted: finalCompleted,
                    stepsTotal: totalSteps
                )
                historyStore.append(entry: entry)
                logRun(entry: entry)

                var updated = wf
                updated.lastRunAt = Date()
                updated.lastRunSuccess = finalSuccess
                self.workflows[workflowId] = updated
                self.persistWorkflowStates()

                self.sendNotification(
                    title: finalSuccess ? "Workflow Complete" : "Workflow Finished",
                    body: "\(wf.name): \(summary)"
                )
            }
            completion?(finalSuccess)
        }
    }

    private var stepOutputs: [String: Any] = [:]
    private let stepOutputsLock = NSLock()

    private func stepOutputValue(_ key: String) -> Any? {
        stepOutputsLock.lock()
        defer { stepOutputsLock.unlock() }
        return stepOutputs[key]
    }

    private func stepSetOutputValue(_ key: String, _ value: Any) {
        stepOutputsLock.lock()
        defer { stepOutputsLock.unlock() }
        stepOutputs[key] = value
    }

    private func stepOutputsSnapshot() -> [String: Any] {
        stepOutputsLock.lock()
        defer { stepOutputsLock.unlock() }
        return stepOutputs
    }

    private func executeStep(_ step: AnalysisPipeline.Workflow.Step, workflowId: String, runId: String) async -> Bool {
        switch step.action {
        case "open_url":
            if let urlString = step.url, let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
                return true
            }
            return false

        case "open_application":
            let appName = step.appName ?? step.url
            if let appName = appName {
                let apps = NSWorkspace.shared.runningApplications
                if let app = apps.first(where: { $0.localizedName == appName }) {
                    app.activate()
                    return true
                }
                let appDirs = [
                    "/Applications",
                    "\(NSHomeDirectory())/Applications",
                ]
                for dir in appDirs {
                    let appPath = "\(dir)/\(appName).app"
                    if FileManager.default.fileExists(atPath: appPath) {
                        let config = NSWorkspace.OpenConfiguration()
                        _ = try? await NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: appPath), configuration: config)
                        return true
                    }
                }
                return false
            }
            return false

        case "type_text":
            if let text = step.data {
                // Resolve inputFrom references: {{step1.output}}
                let resolved = resolveVariables(text, outputs: stepOutputsSnapshot())
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(resolved, forType: .string)
                try? await Task.sleep(nanoseconds: 100_000_000)
                postKeyPress(keyCode: 9, flags: CGEventFlags.maskCommand)
                try? await Task.sleep(nanoseconds: 200_000_000)
                if let outputAs = step.outputAs { stepSetOutputValue(outputAs, resolved) }
                return true
            }
            return false

        case "press_shortcut":
            if let shortcut = step.shortcut {
                return executeShortcut(shortcut)
            }
            return false

        case "copy_clipboard":
            if let text = step.data {
                let resolved = resolveVariables(text, outputs: stepOutputsSnapshot())
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(resolved, forType: .string)
                if let outputAs = step.outputAs { stepSetOutputValue(outputAs, resolved) }
            }
            return true

        case "paste_text":
            postKeyPress(keyCode: 9, flags: CGEventFlags.maskCommand)
            try? await Task.sleep(nanoseconds: 100_000_000)
            return true

        case "click":
            if let pos = step.selector {
                let coords = parseClickCoords(pos)
                postMouseEvent(type: CGEventType.leftMouseDown, point: coords)
                try? await Task.sleep(nanoseconds: 50_000_000)
                postMouseEvent(type: CGEventType.leftMouseUp, point: coords)
                return true
            }
            return false

        case "wait":
            let seconds = step.duration ?? (Double(step.data ?? "2") ?? 2.0)
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return true

        case "web_request":
            return await executeWebRequest(step)

        case "file_read":
            return executeFileRead(step)

        case "file_write":
            return executeFileWrite(step)

        case "extract_data":
            return executeExtractData(step)

        case "transform":
            return executeTransform(step)

        case "condition":
            return executeCondition(step)

        case "send_email":
            // Desktop: open mailto link. n8n: proper email node.
            if let recipients = step.recipients {
                let subject = step.data ?? ""
                let body = step.template ?? ""
                let resolvedBody = resolveVariables(body, outputs: stepOutputsSnapshot())
                let mailto = "mailto:\(recipients)?subject=\(percentEncode(subject))&body=\(percentEncode(resolvedBody))"
                if let url = URL(string: mailto) {
                    NSWorkspace.shared.open(url)
                }
            }
            return true

        case "run_script":
            return executeRunScript(step)

        case "screenshot":
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            let screenshotsDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Mirror/Logs/\(workflowId)")
            try? FileManager.default.createDirectory(at: screenshotsDir, withIntermediateDirectories: true)
            let screenshotPath = screenshotsDir.appendingPathComponent("screenshot_\(runId).png").path
            task.arguments = ["-x", screenshotPath]
            try? task.run()
            task.waitUntilExit()
            if let outputAs = step.outputAs { stepSetOutputValue(outputAs, screenshotPath) }
            return true

        case "gmail_send":
            let to = resolveVariables(step.to ?? "", outputs: stepOutputsSnapshot())
            let subject = resolveVariables(step.subject ?? "", outputs: stepOutputsSnapshot())
            let body = resolveVariables(step.body ?? "", outputs: stepOutputsSnapshot())
            do {
                try await GmailConnector().send(to: to, subject: subject, body: body)
                return true
            } catch {
                print("[Mirror] gmail_send failed: \(error)")
                return false
            }

        case "gmail_search":
            let query = step.query ?? ""
            do {
                let messages = try await GmailConnector().search(query: query)
                if let outputKey = step.outputAs {
                    let encoded = try JSONEncoder().encode(messages)
                    let json = String(data: encoded, encoding: .utf8) ?? "[]"
                    stepSetOutputValue(outputKey, json)
                }
                return true
            } catch {
                print("[Mirror] gmail_search failed: \(error)")
                return false
            }

        case "sheets_append":
            let spreadsheetId = resolveVariables(step.spreadsheetId ?? "", outputs: stepOutputsSnapshot())
            let range = step.range ?? "Sheet1!A:Z"
            let values = (step.values ?? []).map { resolveVariables($0, outputs: stepOutputsSnapshot()) }
            do {
                try await SheetsConnector().appendRow(spreadsheetId: spreadsheetId, range: range, values: values)
                return true
            } catch {
                print("[Mirror] sheets_append failed: \(error)")
                return false
            }

        case "sheets_read":
            let spreadsheetId = resolveVariables(step.spreadsheetId ?? "", outputs: stepOutputsSnapshot())
            let range = step.range ?? "Sheet1!A:Z"
            do {
                let rows = try await SheetsConnector().readRange(spreadsheetId: spreadsheetId, range: range)
                if let outputKey = step.outputAs {
                    let encoded = try JSONEncoder().encode(rows)
                    let json = String(data: encoded, encoding: .utf8) ?? "[]"
                    stepSetOutputValue(outputKey, json)
                }
                return true
            } catch {
                print("[Mirror] sheets_read failed: \(error)")
                return false
            }

        default:
            return true
        }
    }

    // MARK: - Variable Resolution

    private func resolveVariables(_ text: String, outputs: [String: Any]) -> String {
        var result = text
        let pattern = "\\{\\{(\\w+)\\}\\}"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: result.count))
            for match in matches.reversed() {
                if let range = Range(match.range(at: 1), in: result),
                   let replaceRange = Range(match.range, in: result) {
                    let varName = String(result[range])
                    if let value = outputs[varName] {
                        result.replaceSubrange(replaceRange, with: String(describing: value))
                    }
                }
            }
        }
        return result
    }

    private func percentEncode(_ s: String) -> String {
        return s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
    }

    // MARK: - Web Request

    private func executeWebRequest(_ step: AnalysisPipeline.Workflow.Step) async -> Bool {
        guard let urlString = step.url ?? step.data,
              let url = URL(string: resolveVariables(urlString, outputs: stepOutputsSnapshot())) else {
            return false
        }

        let method = step.method ?? "GET"
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30

        if let headers = step.headers {
            for (key, value) in headers {
                request.setValue(resolveVariables(value, outputs: stepOutputsSnapshot()), forHTTPHeaderField: key)
            }
        }

        if let body = step.body {
            request.httpBody = resolveVariables(body, outputs: stepOutputsSnapshot()).data(using: .utf8)
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResp = response as? HTTPURLResponse {
                let success = (200..<300).contains(httpResp.statusCode)
                if let outputAs = step.outputAs ?? step.output {
                    if let str = String(data: data, encoding: .utf8) {
                        stepSetOutputValue(outputAs, str)
                    } else {
                        stepSetOutputValue(outputAs, data)
                    }
                }
                return success
            }
            return false
        } catch {
            return false
        }
    }

    // MARK: - File Operations

    private func executeFileRead(_ step: AnalysisPipeline.Workflow.Step) -> Bool {
        guard let path = step.path ?? step.file else { return false }
        let resolvedPath = resolveVariables(path, outputs: stepOutputsSnapshot()).replacingTildeWithHome
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: resolvedPath)) else { return false }

            if let outputAs = step.outputAs ?? step.output {
            let encoding = step.encoding ?? "utf8"
            if encoding == "base64" {
                stepSetOutputValue(outputAs, data.base64EncodedString())
            } else {
                stepSetOutputValue(outputAs, String(data: data, encoding: .utf8) ?? "")
            }
        }
        return true
    }

    private func executeFileWrite(_ step: AnalysisPipeline.Workflow.Step) -> Bool {
        guard let path = step.path ?? step.file else { return false }
        let resolvedPath = resolveVariables(path, outputs: stepOutputsSnapshot()).replacingTildeWithHome
        let content = resolveVariables(step.data ?? step.template ?? "", outputs: stepOutputsSnapshot())

        do {
            let dir = URL(fileURLWithPath: resolvedPath).deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try content.write(toFile: resolvedPath, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Data Extraction

    private func executeExtractData(_ step: AnalysisPipeline.Workflow.Step) -> Bool {
        var source: String = ""
        if let inputFrom = step.inputFrom, let output = stepOutputValue(inputFrom) {
            source = String(describing: output)
        } else {
            source = NSPasteboard.general.string(forType: .string) ?? ""
        }

        if let pattern = step.extractPattern {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(source.startIndex..., in: source)
                if let match = regex.firstMatch(in: source, options: [], range: range) {
                    if let range = Range(match.range, in: source) {
                        let extracted = String(source[range])
                        if let outputAs = step.outputAs ?? step.output {
                            stepSetOutputValue(outputAs, extracted)
                        }
                    }
                }
            }
        } else {
            if let outputAs = step.outputAs ?? step.output {
                stepSetOutputValue(outputAs, source)
            }
        }
        return true
    }

    // MARK: - Transform

    private func executeTransform(_ step: AnalysisPipeline.Workflow.Step) -> Bool {
        var input: Any = ""
        if let inputFrom = step.inputFrom, let output = stepOutputValue(inputFrom) {
            input = output
        }

        if let transformExpr = step.transform {
            if let outputAs = step.outputAs ?? step.output {
                let inputStr = String(describing: input)
                if transformExpr == "length" { stepSetOutputValue(outputAs, inputStr.count) }
                else if transformExpr == "lowercase" { stepSetOutputValue(outputAs, inputStr.lowercased()) }
                else if transformExpr == "uppercase" { stepSetOutputValue(outputAs, inputStr.uppercased()) }
                else if transformExpr == "trim" { stepSetOutputValue(outputAs, inputStr.trimmingCharacters(in: .whitespacesAndNewlines)) }
                else if transformExpr.hasPrefix("prefix:") { stepSetOutputValue(outputAs, String(transformExpr.dropFirst(7)) + inputStr) }
                else if transformExpr.hasPrefix("suffix:") { stepSetOutputValue(outputAs, inputStr + String(transformExpr.dropFirst(7))) }
                else { stepSetOutputValue(outputAs, inputStr) }
            }
        }
        return true
    }

    // MARK: - Script Execution

    private let allowedScriptCommands: Set<String> = [
        "/usr/bin/curl", "/usr/bin/osascript", "/usr/bin/python3",
        "/usr/bin/open", "/usr/bin/say", "/usr/bin/pbpaste", "/usr/bin/pbcopy",
        "/usr/sbin/screencapture", "/usr/bin/shortcuts"
    ]

    private func isScriptCommandAllowed(_ cmd: String) -> Bool {
        let trimmed = cmd.trimmingCharacters(in: .whitespaces)
        let firstToken = trimmed.components(separatedBy: " ").first ?? ""
        guard !firstToken.isEmpty else { return false }

        if allowedScriptCommands.contains(firstToken) { return true }
        if firstToken.hasPrefix("/usr/bin/") || firstToken.hasPrefix("/usr/sbin/") {
            if FileManager.default.isExecutableFile(atPath: firstToken) { return true }
        }
        return false
    }

    private func executeRunScript(_ step: AnalysisPipeline.Workflow.Step) -> Bool {
        guard let cmd = step.data else { return false }
        let resolved = resolveVariables(cmd, outputs: stepOutputsSnapshot())
        guard isScriptCommandAllowed(resolved) else {
            print("[Mirror] Script blocked by allowlist: \(resolved.prefix(200))")
            return false
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = ["-c", resolved]
        try? task.run()
        task.waitUntilExit()
        return task.terminationStatus == 0
    }

    // MARK: - Condition

    private func executeCondition(_ step: AnalysisPipeline.Workflow.Step) -> Bool {
        guard let condition = step.condition else { return true }

        // Resolve variable references in condition
        let resolved = resolveVariables(condition, outputs: stepOutputsSnapshot())

        // Simple conditions: "{{var}} == value", "{{var}} != value", "{{var}} contains value"
        if resolved.contains("==") {
            let parts = resolved.components(separatedBy: "==").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 { return parts[0] == parts[1] }
        } else if resolved.contains("!=") {
            let parts = resolved.components(separatedBy: "!=").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 { return parts[0] != parts[1] }
        } else if resolved.contains("contains") {
            let parts = resolved.components(separatedBy: "contains").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 { return parts[0].contains(parts[1]) }
        }

        return true
    }

    // MARK: - Keyboard Shortcut

    private func executeShortcut(_ shortcut: String) -> Bool {
        let parts = shortcut.lowercased().components(separatedBy: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        var flags: CGEventFlags = []
        var keyCode: CGKeyCode = 0

        for part in parts {
            switch part {
            case "cmd", "command": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            case "ctrl", "control": flags.insert(.maskControl)
            case "alt", "option": flags.insert(.maskAlternate)
            case "a": keyCode = 0
            case "c": keyCode = 8
            case "v": keyCode = 9
            case "s": keyCode = 1
            case "x": keyCode = 7
            case "z": keyCode = 6
            case "n": keyCode = 45
            case "p": keyCode = 35
            case "w": keyCode = 13
            case "q": keyCode = 12
            case "r": keyCode = 15
            case "t": keyCode = 17
            case "f": keyCode = 3
            case "space": keyCode = 49
            case "enter", "return": keyCode = 36
            case "tab": keyCode = 48
            case "esc", "escape": keyCode = 53
            case "delete", "backspace": keyCode = 51
            default:
                if let num = Int(part) {
                    keyCode = CGKeyCode(num)
                }
            }
        }

        postKeyPress(keyCode: keyCode, flags: flags)
        return true
    }

    // MARK: - launchd Management

    private func launchdPlistPath(workflowId: String) -> String {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("com.mirror.workflow.\(workflowId).plist").path
    }

    private func createLaunchdPlist(workflowId: String, workflow: AnalysisPipeline.Workflow) -> String {
        let path = launchdPlistPath(workflowId: workflowId)
        let mirrorPath = "/Applications/Mirror.app/Contents/MacOS/Mirror"

        var plist: [String: Any] = [
            "Label": "com.mirror.workflow.\(workflowId)",
            "ProgramArguments": [mirrorPath, "--run-workflow", workflowId],
            "RunAtLoad": false,
            "KeepAlive": false,
            "StandardOutPath": FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Mirror/Logs/\(workflowId)/stdout.log").path,
            "StandardErrorPath": FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Mirror/Logs/\(workflowId)/stderr.log").path,
        ]

        if let cron = workflow.trigger.cron, workflow.trigger.type == "schedule" {
            let parts = cron.split(separator: " ")
            if parts.count == 5 {
                var calendar: [String: Any] = [:]
                func parseCronField(_ s: String.SubSequence) -> Int? {
                    let str = String(s)
                    if str == "*" { return nil }
                    if str.hasPrefix("*/"), let interval = Int(str.dropFirst(2)) {
                        return interval
                    }
                    return Int(str)
                }
                if let v = parseCronField(parts[0]) { calendar["Minute"] = v }
                if let v = parseCronField(parts[1]) { calendar["Hour"] = v }
                if let v = parseCronField(parts[2]) { calendar["Day"] = v }
                if let v = parseCronField(parts[3]) { calendar["Month"] = v }
                if let v = parseCronField(parts[4]) { calendar["Weekday"] = v }
                plist["StartCalendarInterval"] = calendar
            }
        }

        if let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
            try? data.write(to: URL(fileURLWithPath: path))
        }

        return path
    }

    private func loadLaunchdJob(plistPath: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["load", plistPath]
        try? process.run()
        process.waitUntilExit()
    }

    private func unloadLaunchdJob(plistPath: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["unload", plistPath]
        try? process.run()
        process.waitUntilExit()
    }

    // MARK: - Persistence

    func persistWorkflowStates() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Mirror/Data")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let url = dir.appendingPathComponent("workflows.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(Array(workflows.values)) {
            try? data.write(to: url)
        }
    }

    func restoreScheduledWorkflows() {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Mirror/Data/workflows.json")
        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        if let saved = try? decoder.decode([DeployedWorkflow].self, from: data) {
            for wf in saved {
                workflows[wf.id] = wf
            }
        }
    }

    // MARK: - Logging

    private func logRun(entry: RunLogEntry) {
        let logDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Mirror/Logs/\(entry.workflowId)")
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let filename = "\(formatter.string(from: entry.timestamp)).json"
        let url = logDir.appendingPathComponent(filename)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(entry) {
            try? data.write(to: url)
        }
    }

    // MARK: - Notifications

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Input Simulation

    private func postKeyPress(keyCode: CGKeyCode, flags: CGEventFlags) {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) else { return }
        event.flags = flags
        event.post(tap: .cghidEventTap)

        if let upEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) {
            upEvent.flags = flags
            upEvent.post(tap: .cghidEventTap)
        }
    }

    private func postMouseEvent(type: CGEventType, point: CGPoint) {
        guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { return }
        event.post(tap: .cghidEventTap)
    }

    private func parseClickCoords(_ selector: String) -> CGPoint {
        let parts = selector.replacingOccurrences(of: " ", with: "").split(separator: ",")
        if parts.count == 2,
           let x = Double(parts[0]),
           let y = Double(parts[1]) {
            return CGPoint(x: x, y: y)
        }
        return .zero
    }
}

extension String {
    var replacingTildeWithHome: String {
        return self.replacingOccurrences(of: "~/", with: NSHomeDirectory() + "/")
    }
}
