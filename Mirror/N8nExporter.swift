import Foundation

class N8nExporter {

    static func export(workflow: AnalysisPipeline.Workflow) -> String {
        var nodes: [[String: Any]] = []
        var connections: [String: Any] = [:]

        let triggerNode = createTriggerNode(trigger: workflow.trigger)
        nodes.append(triggerNode)

        var prevNodeName = triggerNode["name"] as! String

        for (index, step) in workflow.steps.enumerated() {
            guard step.enabled else { continue }
            let node = createStepNode(step: step, index: index)
            let nodeName = node["name"] as! String
            nodes.append(node)

            connections[prevNodeName] = [
                "main": [
                    [["node": nodeName, "type": "main", "index": 0]]
                ]
            ]
            prevNodeName = nodeName
        }

        let result: [String: Any] = [
            "name": workflow.name,
            "active": false,
            "nodes": nodes,
            "connections": connections,
            "settings": ["executionOrder": "v1"]
        ]

        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{}"
    }

    private static func createTriggerNode(trigger: AnalysisPipeline.Workflow.Trigger) -> [String: Any] {
        switch trigger.type {
        case "schedule":
            var params: [String: Any] = [:]
            if let cron = trigger.cron {
                params["rule"] = ["interval": ["field": "cronExpression", "expression": cron]]
            }
            return [
                "id": "trigger",
                "name": "Schedule Trigger",
                "type": "n8n-nodes-base.scheduleTrigger",
                "typeVersion": 1,
                "position": [0, 0],
                "parameters": params
            ]

        case "event":
            return [
                "id": "trigger",
                "name": "Webhook Trigger",
                "type": "n8n-nodes-base.webhook",
                "typeVersion": 1,
                "position": [0, 0],
                "parameters": ["path": trigger.event ?? "trigger", "httpMethod": "POST"]
            ]

        default:
            return [
                "id": "trigger",
                "name": "Manual Trigger",
                "type": "n8n-nodes-base.manualTrigger",
                "typeVersion": 1,
                "position": [0, 0],
                "parameters": [:]
            ]
        }
    }

    private static func createStepNode(step: AnalysisPipeline.Workflow.Step, index: Int) -> [String: Any] {
        let x = 200 + (index * 220)
        let y = 0
        let name = String(step.description.replacingOccurrences(of: " ", with: "_").prefix(30))

        switch step.action {
        case "open_url":
            var params: [String: Any] = ["method": step.method ?? "GET"]
            if let url = step.url { params["url"] = url }
            return makeNode(id: step.id, name: name, type: "n8n-nodes-base.httpRequest", version: 4, position: [x, y], params: params)

        case "web_request":
            var params: [String: Any] = ["method": step.method ?? "GET"]
            if let url = step.url { params["url"] = url }
            if let body = step.body { params["body"] = body }
            if let headers = step.headers { params["headerParameters"] = headers }
            return makeNode(id: step.id, name: name, type: "n8n-nodes-base.httpRequest", version: 4, position: [x, y], params: params)

        case "send_email":
            var params: [String: Any] = [:]
            if let recipients = step.recipients { params["sendTo"] = recipients }
            if let template = step.template { params["message"] = template }
            if let data = step.data { params["subject"] = data }
            return makeNode(id: step.id, name: name, type: "n8n-nodes-base.emailSend", version: 2, position: [x, y], params: params)

        case "file_read":
            var params: [String: Any] = [:]
            if let path = step.path { params["filePath"] = path }
            return makeNode(id: step.id, name: name, type: "n8n-nodes-base.readBinaryFile", version: 1, position: [x, y], params: params)

        case "file_write":
            var params: [String: Any] = [:]
            if let path = step.path { params["filePath"] = path }
            if let data = step.data { params["content"] = data }
            return makeNode(id: step.id, name: name, type: "n8n-nodes-base.writeBinaryFile", version: 1, position: [x, y], params: params)

        case "extract_data":
            var params: [String: Any] = [:]
            if let pattern = step.extractPattern { params["regex"] = pattern }
            return makeNode(id: step.id, name: name, type: "n8n-nodes-base.regularExpression", version: 1, position: [x, y], params: params)

        case "transform":
            var params: [String: Any] = [:]
            if let transform = step.transform { params["expression"] = transform }
            return makeNode(id: step.id, name: name, type: "n8n-nodes-base.set", version: 3, position: [x, y], params: params)

        case "condition":
            var params: [String: Any] = [:]
            if let cond = step.condition { params["conditions"] = cond }
            return makeNode(id: step.id, name: name, type: "n8n-nodes-base.if", version: 1, position: [x, y], params: params)

        case "wait":
            var params: [String: Any] = ["unit": "seconds"]
            if let dur = step.duration { params["amount"] = dur }
            return makeNode(id: step.id, name: name, type: "n8n-nodes-base.wait", version: 1, position: [x, y], params: params)

        case "run_script":
            var params: [String: Any] = [:]
            if let cmd = step.data { params["command"] = cmd }
            return makeNode(id: step.id, name: name, type: "n8n-nodes-base.executeCommand", version: 1, position: [x, y], params: params)

        default:
            let note = "Local action: \(step.action) — \(step.description). Runs on macOS via Mirror desktop."
            return makeNode(id: step.id, name: name, type: "n8n-nodes-base.noOp", version: 1, position: [x, y], params: ["note": note])
        }
    }

    private static func makeNode(id: String, name: String, type: String, version: Int, position: [Int], params: [String: Any]) -> [String: Any] {
        var node: [String: Any] = [
            "id": id,
            "name": name,
            "type": type,
            "typeVersion": version,
            "position": position
        ]
        if !params.isEmpty {
            node["parameters"] = params
        }
        return node
    }
}