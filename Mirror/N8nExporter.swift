import Foundation

class N8nExporter {

    static func export(workflow: AnalysisPipeline.Workflow) -> String {
        var nodes: [[String: Any]] = []
        var connections: [String: [String: [[[String: Any]]]]] = [:]

        // Trigger
        let triggerName = "Schedule_Trigger"
        nodes.append(createTriggerNode(trigger: workflow.trigger))

        var prevName = triggerName
        var nodeX = 250

        for (index, step) in workflow.steps.enumerated() where step.enabled {
            let node = createStepNode(step: step, index: index, x: nodeX)
            let nodeName = node["name"] as? String ?? "Step \(index)"

            nodes.append(node)
            connections[prevName] = ["main": [[["node": nodeName, "type": "main", "index": 0]]]]
            prevName = nodeName
            nodeX += 280
        }

        let result: [String: Any] = [
            "name": workflow.name,
            "nodes": nodes,
            "connections": connections,
            "settings": ["executionOrder": "v1"],
            "staticData": NSNull(),
            "pinData": [String: Any](),
            "versionId": UUID().uuidString,
            "active": false,
            "id": UUID().uuidString,
            "createdAt": ISO8601DateFormatter().string(from: Date()),
            "updatedAt": ISO8601DateFormatter().string(from: Date())
        ]

        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{}"
    }

    // MARK: - Trigger

    private static func createTriggerNode(trigger: AnalysisPipeline.Workflow.Trigger) -> [String: Any] {
        let base: [String: Any] = ["id": "trigger", "position": [0, 300]]
        switch trigger.type {
        case "schedule":
            var node = base
            node["name"] = "Schedule Trigger"
            node["type"] = "n8n-nodes-base.scheduleTrigger"
            node["typeVersion"] = 1
            if let cron = trigger.cron {
                node["parameters"] = ["rule": ["interval": [["field": "cronExpression", "expression": cron]]]]
            }
            return node
        case "event":
            var node = base
            node["name"] = "Webhook"
            node["type"] = "n8n-nodes-base.webhook"
            node["typeVersion"] = 1
            node["parameters"] = ["path": trigger.event ?? "trigger", "httpMethod": "POST"]
            return node
        default:
            var node = base
            node["name"] = "Manual Trigger"
            node["type"] = "n8n-nodes-base.manualTrigger"
            node["typeVersion"] = 1
            return node
        }
    }

    // MARK: - Step Mapping

    private static func createStepNode(step: AnalysisPipeline.Workflow.Step, index: Int, x: Int) -> [String: Any] {
        let name = sanitizeName(step.description.isEmpty ? step.action : step.description)
        let y = 250 + (index % 3) * 180

        let (type, version, params) = mapToN8n(step: step)

        var node: [String: Any] = [
            "id": step.id,
            "name": name,
            "type": type,
            "typeVersion": version,
            "position": [x, y]
        ]
        if !params.isEmpty { node["parameters"] = params }

        // Add credential reference for OAuth-based nodes
        if requiresCredential(type) {
            node["credentials"] = ["googleOAuth2Api": ["id": "1", "name": "Google account"]]
        }

        return node
    }

    private static func mapToN8n(step: AnalysisPipeline.Workflow.Step) -> (type: String, version: Int, params: [String: Any]) {
        let desc = step.description
        var p: [String: Any] = [:]

        switch step.action {
        // ═══════ Gmail ═══════
        case "gmail_search":
            if let q = step.query { p["query"] = q }
            return ("n8n-nodes-base.gmail", 3, p)
        case "gmail_fetch", "gmail_open_email":
            return ("n8n-nodes-base.gmail", 3, ["operation": "get", "id": "{{$json.id}}"])
        case "gmail_send", "send_email":
            if let to = step.to { p["sendTo"] = to }
            if let subject = step.subject { p["subject"] = subject }
            if let body = step.body { p["message"] = body }
            return ("n8n-nodes-base.gmail", 3, p)

        // ═══════ Sheets ═══════
        case "sheets_read", "spreadsheet_read":
            if let id = step.spreadsheetId { p["sheetId"] = id }
            if let range = step.range { p["range"] = range }
            return ("n8n-nodes-base.googleSheets", 4, p)
        case "sheets_append", "append_sheet_row":
            if let id = step.spreadsheetId { p["sheetId"] = id }
            if let range = step.range { p["range"] = range }
            if let vals = step.values { p["valueInput"] = vals }
            return ("n8n-nodes-base.googleSheets", 4, p)
        case "sheets_create":
            return ("n8n-nodes-base.googleSheets", 4, ["operation": "create"])

        // ═══════ Slack ═══════
        case "slack_post":
            if let text = step.data { p["text"] = text }
            return ("n8n-nodes-base.slack", 3, p)
        case "slack_upload":
            return ("n8n-nodes-base.slack", 3, ["operation": "upload"])

        // ═══════ HTTP ═══════
        case "http_request", "web_request", "open_url":
            p["method"] = step.method ?? "GET"
            if let url = step.url { p["url"] = url }
            if let body = step.body { p["bodyParameters"] = body }
            if let headers = step.headers { p["headerParameters"] = headers }
            return ("n8n-nodes-base.httpRequest", 4, p)

        // ═══════ AI ═══════
        case "ai_summarize", "summarize":
            p["prompt"] = "Summarize: " + (step.description)
            return ("n8n-nodes-base.openAi", 2, p)
        case "ai_classify", "classify":
            return ("n8n-nodes-base.openAi", 2, ["prompt": "Classify: " + desc])
        case "ai_translate":
            return ("n8n-nodes-base.openAi", 2, ["prompt": "Translate: " + desc])
        case "ai_extract":
            return ("n8n-nodes-base.openAi", 2, ["prompt": "Extract: " + desc])

        // ═══════ Data ═══════
        case "extract_data", "extract_fields":
            if let pat = step.extractPattern { p["regex"] = pat }
            return ("n8n-nodes-base.set", 3, p)
        case "map_fields":
            return ("n8n-nodes-base.set", 3, ["keepOnlySet": true])
        case "filter":
            if let cond = step.condition { p["conditions"] = cond }
            return ("n8n-nodes-base.filter", 1, p)
        case "sort_data":
            return ("n8n-nodes-base.sort", 1, p)
        case "aggregate":
            return ("n8n-nodes-base.aggregate", 1, p)
        case "merge_data":
            return ("n8n-nodes-base.merge", 3, p)
        case "split_data":
            return ("n8n-nodes-base.splitInBatches", 3, ["batchSize": 10])
        case "deduplicate":
            return ("n8n-nodes-base.removeDuplicates", 1, p)
        case "parse_json":
            return ("n8n-nodes-base.itemLists", 3, ["operation": "parseJson"])
        case "parse_csv":
            return ("n8n-nodes-base.spreadsheetFile", 1, ["operation": "fromFile"])

        // ═══════ Logic ═══════
        case "condition", "if_condition":
            return ("n8n-nodes-base.if", 2, p)
        case "switch":
            return ("n8n-nodes-base.switch", 3, p)
        case "loop":
            return ("n8n-nodes-base.splitInBatches", 3, ["batchSize": 1])
        case "wait":
            if let dur = step.duration { p["amount"] = Int(dur) }
            return ("n8n-nodes-base.wait", 1, p)
        case "random":
            return ("n8n-nodes-base.code", 1, ["jsCode": "return Math.random()"])
        case "set_variable":
            return ("n8n-nodes-base.set", 3, p)
        case "get_variable":
            return ("n8n-nodes-base.set", 3, p)

        // ═══════ Files/Media ═══════
        case "file_read":
            return ("n8n-nodes-base.readBinaryFiles", 1, ["filePath": step.path ?? step.file ?? ""])
        case "file_write", "create_file":
            var fp: [String: Any] = ["content": step.data ?? ""]
            if let path = step.path { fp["filePath"] = path }
            return ("n8n-nodes-base.writeBinaryFile", 1, fp)
        case "screenshot", "take_screenshot":
            return ("n8n-nodes-base.screenshot", 1, p)

        // ═══════ Email ═══════
        case "email_received":
            return ("n8n-nodes-base.emailReadImap", 2, p)
        case "sms_send":
            return ("n8n-nodes-base.twilio", 1, ["content": desc])

        // ═══════ Code ═══════
        case "run_script", "code_bash", "code_python", "code_javascript":
            p["language"] = step.action == "code_python" ? "python" : step.action == "code_javascript" ? "javaScript" : "bash"
            return ("n8n-nodes-base.code", 2, p)

        // ═══════ Databases ═══════
        case "pg_query", "mysql_query":
            return ("n8n-nodes-base.postgres", 2, ["query": desc])
        case "mongo_find":
            return ("n8n-nodes-base.mongoDb", 2, ["collection": "default"])

        // ═══════ Calendar ═══════
        case "gcal_create", "gcal_read", "gcal_update", "gcal_delete":
            p["operation"] = step.action == "gcal_create" ? "create" : step.action == "gcal_read" ? "getAll" : step.action == "gcal_update" ? "update" : "delete"
            return ("n8n-nodes-base.googleCalendar", 2, p)

        // ═══════ Notifications ═══════
        case "notify_user":
            return ("n8n-nodes-base.webhook", 1, ["responseMode": "responseNode"])

        // ═══════ Approval ═══════
        case "approval_required":
            return ("n8n-nodes-base.wait", 1, ["resume": "webhook"])

        // ═══════ Desktop/Local (fallback to Note + HTTP) ═══════
        case "open_application", "open_app":
            return ("n8n-nodes-base.executeCommand", 1, ["command": "open -a \"\(step.appName ?? "Safari")\""])
        case "type_text", "click", "click_element", "click_ui_element", "press_shortcut", "paste_text", "copy_to_clipboard", "navigate_url", "fill_form", "scroll_page":
            // Desktop-only steps: export as Sticky Note explaining they require Mirror
            return ("n8n-nodes-base.stickyNote", 1, ["content": "⚠ Mirror Desktop Step\n\n\(step.action): \(step.description)\n\nThis step requires Mirror running on macOS. It cannot execute in n8n alone."])

        // ═══════ Default: HTTP Request as generic fallback ═══════
        default:
            return ("n8n-nodes-base.httpRequest", 4, ["url": "", "method": "GET", "notes": "Mirror step: \(step.action) — \(step.description)"])
        }
    }

    // MARK: - Helpers

    private static func sanitizeName(_ name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: ".", with: "_")
        return String(cleaned.prefix(40))
    }

    private static func requiresCredential(_ nodeType: String) -> Bool {
        return nodeType.contains("gmail") || nodeType.contains("googleSheets") ||
               nodeType.contains("googleCalendar") || nodeType.contains("googleDrive")
    }
}
