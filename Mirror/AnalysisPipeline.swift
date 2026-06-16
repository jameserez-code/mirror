import Foundation

struct AnalysisPipeline {

    // MARK: - Workflow JSON Schema

    struct Workflow: Codable {
        var name: String
        var trigger: Trigger
        var steps: [Step]
        let confidence: Double
        let requiresReview: [String]
        let scheduleRecommendation: String?
        let exportTargets: [String]?

        struct Trigger: Codable {
            let type: String
            let cron: String?
            let description: String
            let event: String?
        }

        struct Step: Codable {
            let id: String
            let action: String
            var description: String
            var enabled: Bool
            let requiresReview: Bool

            // Action-specific fields
            let url: String?
            let selector: String?
            let output: String?
            let file: String?
            let data: String?
            let template: String?
            let recipients: String?
            let appName: String?

            // Semantic fields for n8n/automation
            let inputFrom: String?
            let outputAs: String?
            let condition: String?

            // HTTP/web request fields
            let method: String?
            let headers: [String: String]?
            let body: String?

            // File operations
            let path: String?
            let encoding: String?

            // Data transformation
            let extractPattern: String?
            let transform: String?

            // Wait/delay
            let duration: Double?

            // Keyboard shortcut
            let shortcut: String?

            // Gmail fields
            let to: String?
            let subject: String?
            let query: String?

            // Sheets fields
            let spreadsheetId: String?
            let range: String?
            let values: [String]?

            // Execution type: "cloud" or "local"
            let executionType: String?
        }
    }

    // MARK: - System Prompt

    static let systemPrompt = """
        You are Mirror's expert workflow automation engine. You create production-ready automations that actually work.

        ## WORKFLOW DECOMPOSITION RULES

        Break every workflow into these distinct STEP TYPES. Never merge steps — each action is its own step:

        1. DATA SOURCE — Where does information come from? (gmail_search, sheets_read, file_read, http_request)
        2. EXTRACTION — What data is pulled out? (extract_data, ai_extract)
        3. TRANSFORMATION — How is data changed? (filter, sort, transform, condition)
        4. DESTINATION — Where does data go? (sheets_append, gmail_send, slack_post, file_write)

        Example decomposition of "Process invoices from Gmail to Sheets":
        step1: gmail_search (data source — find invoice emails)
        step2: gmail_fetch (data source — open each email)  
        step3: extract_data (extraction — pull invoice number, amount, vendor)
        step4: condition (transformation — only process if amount > 0)
        step5: sheets_append (destination — log to tracker sheet)

        Example decomposition of "Send daily Slack report":
        step1: sheets_read (data source — pull data from report sheet)
        step2: transform (transformation — format data as message)
        step3: slack_post (destination — post to channel)

        ## DATA FLOW RULES

        When data moves between steps, ALWAYS connect them with outputAs/inputFrom:
        - Step that PRODUCES data: outputAs="variable_name"
        - Step that CONSUMES data: inputFrom="variable_name"

        Example:
        step1: gmail_search → outputAs="invoice_emails"
        step2: extract_data → inputFrom="invoice_emails", outputAs="invoice_data"
        step3: sheets_append → inputFrom="invoice_data"

        ## TRIGGER SELECTION

        - If the user does this daily/weekly/monthly → schedule trigger with appropriate cron
        - If it's an ad-hoc task → manual trigger
        - If it responds to external events → webhook trigger
        Common cron patterns:
        - Daily at 9am: "0 9 * * *"
        - Weekdays at 9am: "0 9 * * 1-5"
        - Every Monday 9am: "0 9 * * 1"
        - Every hour: "0 * * * *"
        - Monthly 1st at 9am: "0 9 1 * *"

        ## CONFIDENCE SCORING

        Base confidence: 0.70
        +0.20 if ALL steps are cloud/API (no desktop replay)
        +0.10 if data flow is fully connected (outputAs/inputFrom on all steps)
        +0.05 if trigger is clearly identified
        -0.10 if any step requires desktop interaction
        -0.15 if workflow has gaps or unclear intent
        -0.20 if relying on click coordinates

        ## ACTION SELECTION PRIORITY

        Prefer cloud API actions over desktop replay. Use these mappings:
        - Gmail → gmail_search, gmail_fetch, gmail_send
        - Google Sheets → sheets_read, sheets_append
        - Slack → slack_post
        - Any HTTP API → http_request
        - Email (non-Gmail) → send_email
        - File operations → file_read, file_write
        - Data processing → extract_data, filter, transform, condition
        - Desktop-only apps → open_application, type_text (LAST RESORT)

        ## STEP NAMING

        Each step description should be a clear, action-oriented phrase:
        - "Search Gmail for recent invoices"
        - "Extract invoice number, amount, and vendor"
        - "Append extracted data to Accounts Payable sheet"
        - NOT "click", "type", "do stuff"

        ## COMPLETE ACTION LIST (use these EXACT values for the 'action' field)

        Cloud API actions:
        - gmail_search: query, outputAs
        - gmail_fetch: outputAs  
        - gmail_send: to, subject, body
        - sheets_read: spreadsheetId, range, outputAs
        - sheets_append: spreadsheetId, range, values
        - slack_post: text
        - http_request: url, method, headers, body
        - send_email: to, subject, body
        - notify_user: description
        - approval_required: description

        Data processing actions:
        - extract_data: pattern, inputFrom, outputAs
        - filter: condition, inputFrom, outputAs
        - transform: transform, inputFrom, outputAs
        - condition: condition
        - wait: duration

        Desktop actions (fallback only):
        - open_application: appName
        - type_text: data
        - click: selector
        - press_shortcut: shortcut
        - file_read: path, outputAs
        - file_write: path, data
        - run_script: data
        - screenshot: path

        ## OUTPUT FORMAT

        Output ONLY valid JSON matching this EXACT schema. No markdown, no explanation:
        {
          "name": "Concise verb-based workflow name",
          "trigger": {"type": "schedule|manual", "cron": "cron or null", "description": "human readable", "event": null},
          "steps": [{
            "id": "step1", "action": "action_type", "description": "plain English",
            "enabled": true, "requiresReview": false, "executionType": "cloud|local",
            "inputFrom": null, "outputAs": null,
            "query": null, "to": null, "subject": null, "body": null,
            "spreadsheetId": null, "range": null, "values": null,
            "url": null, "method": null, "data": null, "pattern": null,
            "condition": null, "duration": null, "appName": null
          }],
          "confidence": 0.0-1.0,
          "requiresReview": [],
          "scheduleRecommendation": null
        }

        EVERY step MUST have: id, action, description, enabled, requiresReview, executionType.
        Steps with data flow MUST have: inputFrom and/or outputAs.
        Steps requiring API credentials should have requiresReview: true.
        """


    // MARK: - User Prompt Builder

    static func buildUserPrompt(timeline: String, metadata: [String: Any], events: [EventTapManager.CapturedEvent], visionDescriptions: String = "") -> String {
        let duration = (metadata["duration"] as? Double) ?? 0
        let eventCount = (metadata["eventCount"] as? Int) ?? 0
        let extraContext = (metadata["extraContext"] as? String) ?? ""

        let semanticActions = SemanticActionExtractor.extract(from: events)
        let semanticContext = SemanticActionExtractor.buildContextSummary(from: events)
        let intentPlan = WorkflowIntentExtractor.extract(from: semanticActions, events: events)
        let graph = WorkflowGraphBuilder.buildFullGraph(from: semanticActions, artifacts: intentPlan.artifacts, intent: intentPlan.intent, events: events)
        let entityGraph = EntityGraphBuilder.build(events: events, actions: semanticActions, artifacts: intentPlan.artifacts, graph: graph)

        var state = BeliefStateEngine.initialize(sessionId: "analysis")
        BeliefStateEngine.update(&state, events: events, partialActions: semanticActions, partialArtifacts: intentPlan.artifacts)
        let snapshot = BeliefStateEngine.snapshot(from: state)

        return """
            Recording Summary: \(String(format: "%.1f", duration))s, \(eventCount) events captured.

            VISION ANALYSIS (AI-described screenshots at 1fps, up to 120 frames):
            \(visionDescriptions.isEmpty ? "(No frames available)" : visionDescriptions)

            \(extraContext.isEmpty ? "" : "USER-PROVIDED CONTEXT (highest priority — the user told us what they were doing):\n\(extraContext)\n")

            \(semanticContext)

            WORKFLOW UNDERSTANDING (pre-extracted — verify against vision + timeline):
            Intent: \(snapshot.projectedIntent?.objective ?? "unknown") (\(snapshot.projectedIntent?.domain ?? "general")) @ \(String(format: "%.0f", (snapshot.projectedIntent?.confidence ?? 0) * 100))%
            Goal: \(snapshot.projectedGoal?.type ?? "general_automation") @ \(String(format: "%.0f", (snapshot.projectedGoal?.confidence ?? 0) * 100))%
            Belief convergence: \(snapshot.converged ? "high" : "low") — entropy: \(String(format: "%.2f", snapshot.overallEntropy))
            Entities detected: \(snapshot.projectedEntityCount) | Nodes detected: \(snapshot.projectedNodeCount)

            \(EntityGraphBuilder.buildEntityGraphSummary(from: entityGraph))

            \(WorkflowGraphBuilder.buildGraphSummary(from: graph))

            RAW EVENT TIMELINE + OCR TEXT:
            \(timeline)

            CRITICAL: The pre-extracted data above is heuristic — it may be wrong. You are the primary analysis engine. Compare the heuristic suggestions against the raw timeline carefully. The screenshots are captured every 0.5 seconds with OCR on 20 sampled frames. Look for:
            1. What app/site the user was actually using (check URLs, app names, OCR window titles)
            2. What data was typed, copied, or pasted (check clipboard snapshots and key sequences)
            3. What actions were performed (clicks, keyboard shortcuts, form submissions)
            4. The ORDER of operations — was searching done before composing? Before pasting?
            5. Data flow — did clipboard content end up in a form field? Did a spreadsheet URL appear in the browser?

            Output valid JSON matching the Workflow schema. Every step MUST have: id, action (from the action list), description, executionType, enabled, requiresReview. Add inputFrom/outputAs for data flow between steps. Cloud steps (gmail_*, sheets_*, http_request, slack_post, send_email) are preferred over desktop replay when the activity clearly happens in those apps.
            """
    }

    // MARK: - API Call

    @discardableResult
    static func analyze(events: [EventTapManager.CapturedEvent],
                        sessionId: String,
                        metadata: [String: Any],
                        progressCallback: ((String) -> Void)? = nil,
                        completion: @escaping (Result<Workflow, AnalysisError>) -> Void) -> URLSessionDataTask? {
        let sessionDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Mirror/Sessions/\(sessionId)")

        let timeline: String
        if FileManager.default.fileExists(atPath: sessionDir.appendingPathComponent("events.json").path) {
            timeline = SessionPackager.shared.buildRichActivityTimeline(events: events, sessionDir: sessionDir)
        } else {
            timeline = SessionPackager.shared.buildActivityTimeline(events: events)
        }

        // Stage 1: Vision analysis on frames (async in background)
        progressCallback?("Analyzing screenshots with vision AI...")
        Task {
            var visionContext = ""
            let framesDir = sessionDir.appendingPathComponent("frames")
            if FileManager.default.fileExists(atPath: framesDir.path) {
                visionContext = await VisionFrameAnalyzer.analyzeFrames(sessionDir: sessionDir) { current, total in
                    progressCallback?("Vision: \(current)/\(total) frames analyzed")
                }
            }

            // Stage 2: Main analysis with vision context
            progressCallback?("Generating workflow...")
            let userPrompt = buildUserPrompt(timeline: timeline, metadata: metadata, events: events, visionDescriptions: visionContext)

            let provider = Settings.apiProvider
            switch provider {
            case "anthropic":
                _ = analyzeWithAnthropic(systemPrompt: systemPrompt, userPrompt: userPrompt, completion: completion)
            case "openai":
                _ = analyzeWithOpenAI(systemPrompt: systemPrompt, userPrompt: userPrompt, completion: completion)
            case "openrouter":
                _ = analyzeWithOpenRouter(systemPrompt: systemPrompt, userPrompt: userPrompt, completion: completion)
            default:
                _ = analyzeWithOpenRouter(systemPrompt: systemPrompt, userPrompt: userPrompt, completion: completion)
            }
        }

        return nil
    }

    // MARK: - Anthropic API

    private static func analyzeWithAnthropic(systemPrompt: String, userPrompt: String, completion: @escaping (Result<Workflow, AnalysisError>) -> Void) -> URLSessionDataTask? {
        guard let apiKey = CredentialStore.shared.getAPIKey(provider: "anthropic") else {
            completion(.failure(.noAPIKey))
            return nil
        }

        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 4096,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": userPrompt]
            ]
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        let session = URLSession(configuration: config)

        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(.networkError(error.localizedDescription)))
                return
            }

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(.failure(.invalidResponse))
                return
            }

            if let content = json["content"] as? [[String: Any]],
               let firstContent = content.first,
               let text = firstContent["text"] as? String {
                parseWorkflowJSON(text, completion: completion)
            } else if let errorObj = json["error"] as? [String: Any],
                      let message = errorObj["message"] as? String {
                completion(.failure(.apiError(message)))
            } else {
                completion(.failure(.invalidResponse))
            }
        }
        task.resume()
        return task
    }

    // MARK: - OpenAI API

    private static func analyzeWithOpenAI(systemPrompt: String, userPrompt: String, completion: @escaping (Result<Workflow, AnalysisError>) -> Void) -> URLSessionDataTask? {
        guard let apiKey = CredentialStore.shared.getAPIKey(provider: "openai") else {
            completion(.failure(.noAPIKey))
            return nil
        }

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "gpt-4o",
            "max_tokens": 4096,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ]
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        let session = URLSession(configuration: config)

        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(.networkError(error.localizedDescription)))
                return
            }

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(.failure(.invalidResponse))
                return
            }

            if let choices = json["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any],
               let text = message["content"] as? String {
                parseWorkflowJSON(text, completion: completion)
            } else if let errorObj = json["error"] as? [String: Any],
                      let message = errorObj["message"] as? String {
                completion(.failure(.apiError(message)))
            } else {
                completion(.failure(.invalidResponse))
            }
        }
        task.resume()
        return task
    }

    // MARK: - OpenRouter API

    private static func analyzeWithOpenRouter(systemPrompt: String, userPrompt: String, completion: @escaping (Result<Workflow, AnalysisError>) -> Void) -> URLSessionDataTask? {
        guard let apiKey = CredentialStore.shared.getAPIKey(provider: "openrouter") else {
            completion(.failure(.noAPIKey))
            return nil
        }

        let url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://mirror.app", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Mirror", forHTTPHeaderField: "X-Title")

        let body: [String: Any] = [
            "model": Settings.openRouterModel,
            "max_tokens": 4096,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ]
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        let session = URLSession(configuration: config)

        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(.networkError(error.localizedDescription)))
                return
            }

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(.failure(.invalidResponse))
                return
            }

            if let choices = json["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any],
               let text = message["content"] as? String {
                parseWorkflowJSON(text, completion: completion)
            } else if let errorObj = json["error"] as? [String: Any],
                      let msg = errorObj["message"] as? String {
                completion(.failure(.apiError(msg)))
            } else {
                completion(.failure(.invalidResponse))
            }
        }
        task.resume()
        return task
    }

    // MARK: - Key Testing

    static func testConnection(provider: String) async -> Bool {
        switch provider {
        case "openrouter":
            guard let key = CredentialStore.shared.getAPIKey(provider: "openrouter") else { return false }
            var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/auth/key")!)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                return (response as? HTTPURLResponse)?.statusCode == 200
            } catch { return false }
        case "anthropic":
            guard let key = CredentialStore.shared.getAPIKey(provider: "anthropic") else { return false }
            var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            request.httpMethod = "POST"
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: [
                "model": "claude-haiku-4-5-20250514",
                "max_tokens": 1,
                "messages": [["role": "user", "content": "hi"]]
            ])
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                return (response as? HTTPURLResponse)?.statusCode == 200
            } catch { return false }
        case "openai":
            guard let key = CredentialStore.shared.getAPIKey(provider: "openai") else { return false }
            var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                return (response as? HTTPURLResponse)?.statusCode == 200
            } catch { return false }
        default:
            return false
        }
    }

    // MARK: - Valid Actions

    static let validActions: Set<String> = [
        "open_url", "open_application", "type_text", "press_shortcut",
        "click", "wait", "copy_clipboard", "paste_text", "extract_data",
        "web_request", "send_email", "file_read", "file_write",
        "run_script", "screenshot", "condition", "transform",
        "gmail_send", "gmail_search", "sheets_append", "sheets_read"
    ]

    // MARK: - Response Parser

    private static func parseWorkflowJSON(_ text: String, completion: @escaping (Result<Workflow, AnalysisError>) -> Void) {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            let lines = cleaned.components(separatedBy: "\n")
            cleaned = lines.dropFirst().dropLast().joined(separator: "\n")
        }
        if cleaned.hasPrefix("json") { cleaned = String(cleaned.dropFirst(4)) }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonData = cleaned.data(using: .utf8) else {
            completion(.failure(.parseError("Could not convert text to data")))
            return
        }

        do {
            let workflow = try JSONDecoder().decode(Workflow.self, from: jsonData)
            // Validate all step actions are known
            for step in workflow.steps {
                guard validActions.contains(step.action) else {
                    completion(.failure(.parseError("Unknown action '\(step.action)' in step \(step.id)")))
                    return
                }
            }
            completion(.success(workflow))
        } catch {
            if var dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                if dict["trigger"] == nil {
                    dict["trigger"] = ["type": "manual", "cron": nil, "description": "Trigger manually", "event": nil]
                }
                if dict["steps"] == nil { dict["steps"] = [] }
                if dict["confidence"] == nil { dict["confidence"] = 0.0 }
                if dict["requiresReview"] == nil { dict["requiresReview"] = [] }

                // Ensure each step has an id
                if var steps = dict["steps"] as? [[String: Any]] {
                    for i in 0..<steps.count {
                        if steps[i]["id"] == nil {
                            steps[i]["id"] = "step\(i + 1)"
                        }
                    }
                    dict["steps"] = steps
                }

                if let patchedData = try? JSONSerialization.data(withJSONObject: dict),
                   let wf = try? JSONDecoder().decode(Workflow.self, from: patchedData) {
                    completion(.success(wf))
                    return
                }
            }
            completion(.failure(.parseError("JSON parse failed: \(error.localizedDescription)")))
        }
    }

    // MARK: - Errors

    enum AnalysisError: Error, LocalizedError {
        case noAPIKey
        case networkError(String)
        case invalidResponse
        case apiError(String)
        case parseError(String)

        var errorDescription: String? {
            switch self {
            case .noAPIKey: return "No API key configured. Add one in Settings."
            case .networkError(let msg): return "Network error: \(msg)"
            case .invalidResponse: return "Invalid response from AI provider"
            case .apiError(let msg): return "API error: \(msg)"
            case .parseError(let msg): return "Failed to parse workflow: \(msg)"
            }
        }
    }
}