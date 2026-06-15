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
        You are Mirror's workflow intelligence engine. You convert raw screen recordings into structured, deployable automations.

        You receive an activity log with:
        - Keyboard/mouse events with timestamps and target application names
        - OCR-extracted text from screen captures showing what the user saw
        - Clipboard snapshots
        - Browser URLs when visible

        Your job:
        1. Identify the CORE workflow — strip navigation noise, auth setup, and dead ends
        2. Determine the best trigger (schedule or event)
        3. Generate steps that are SEMANTIC and REUSABLE — not fragile coordinate-based replays
        4. Map steps to automation-ready actions that work locally AND in n8n/Zapier
        5. Flag steps needing human review (credentials, destructive actions, low confidence)

        CRITICAL RULES:
        - Never include login/authentication steps — flag them as needing review
        - Never replay raw click coordinates — promote "click at (x,y)" to semantic actions like "open_application" or "type_text"
        - Group rapid keystrokes into meaningful typing actions ("type_text" with the full string)
        - When OCR shows form fields, labels, or button text, use that as context to name steps
        - If the user copies data, that's likely an "extract_data" step — data flows INTO clipboard
        - If the user pastes, that's likely "paste_text" — data flows FROM clipboard
        - Prefer high-level actions: open_url > open_application > click > type_text
        - Add "inputFrom" references when one step's output feeds another step's input
        - Every step gets a unique "id" (e.g., "step1", "step2")
        - Confidence reflects how automatable this workflow is without human intervention
        - Output ONLY valid JSON. No prose, no markdown, no code fences.

        ## CLOUD ACTION DETECTION (Critical — check this FIRST for every step)

        Before classifying any step as a local desktop action (click, type_text, paste, 
        press_shortcut), check whether the target app/site is Gmail or Google Sheets.
        If it is, use the corresponding CLOUD action instead. Cloud actions run via API
        and work even when Mirror is not actively controlling the screen — they are 
        far more reliable than desktop replay.

        ### Gmail Detection
        If the activity timeline shows the user in Gmail (gmail.com, or Mail.app with 
        a Google account) composing and sending an email:
        - Emit a single `gmail_send` step instead of multiple click/type steps
        - Extract: to (recipient), subject, body
        - If recipient/subject/body reference data from earlier steps, use {{variable}} syntax

        If the user searches/filters their Gmail inbox:
        - Emit a `gmail_search` step
        - Extract: query (the search query in Gmail search syntax, e.g. "from:stripe subject:invoice")
        - outputAs: variable name for matching messages the user can reference in later steps

        ### Google Sheets Detection
        If the activity timeline shows the user in a Google Sheet (docs.google.com/spreadsheets) 
        typing data into cells, especially appending a new row:
        - Emit a `sheets_append` step instead of click/type steps
        - Extract: spreadsheetId (from the URL if visible in OCR/browser context), 
          range (e.g. "Sheet1!A:Z"), and values as an array of strings
        - If values reference earlier step outputs, use {{variable}} syntax for each cell

        If the user reads/copies data FROM a Google Sheet:
        - Emit a `sheets_read` step
        - Extract: spreadsheetId, range
        - outputAs: variable name for the cell data for use in later steps

        ### executionType field (REQUIRED on EVERY step)
        Every step must include an "executionType" field:
        - "cloud" — for gmail_send, gmail_search, sheets_append, sheets_read, web_request
        - "local" — for click, type_text, paste, press_shortcut, open_application, 
          copy_clipboard, run_script, screenshot
        This field is used by the UI to show which steps run via API (reliable, always works)
        vs which require Mirror running on their Mac (desktop replay).

        ### Confidence Impact
        Workflows composed ENTIRELY of "cloud" steps should receive a confidence BONUS 
        of +0.15 (capped at 1.0), because cloud/API execution is significantly more 
        reliable than desktop replay. Workflows with a MIX of cloud and local steps 
        get no bonus or penalty. Workflows that are ENTIRELY local steps should be 
        penalized -0.1, as these are the least reliable pattern.

        Step actions (use these exactly):
        - open_url: Open a URL in default browser. Fields: url
        - open_application: Launch a desktop app. Fields: appName
        - type_text: Type a string. Fields: data (the text), shortcut (optional key combo like "cmd+a")
        - press_shortcut: Press a keyboard shortcut. Fields: shortcut (e.g., "cmd+c", "cmd+v", "cmd+s")
        - click: Click at position (last resort, fragile). Fields: selector (x,y coordinates)
        - wait: Pause execution. Fields: duration (seconds)
        - copy_clipboard: Copy text to clipboard. Fields: data
        - paste_text: Paste from clipboard (Cmd+V)
        - extract_data: Extract data from screen/clipboard. Fields: extractPattern (regex or selector), outputAs (variable name)
        - web_request: Make an HTTP request. Fields: method, url, headers, body
        - send_email: Send an email. Fields: recipients, template, data
        - file_read: Read a file. Fields: path, outputAs
        - file_write: Write a file. Fields: path, data, template
        - run_script: Run a shell command. Fields: data (the command)
        - screenshot: Capture screenshot for verification
        - condition: Branch based on condition. Fields: condition, data
        - transform: Transform/resize data between steps. Fields: transform, inputFrom, outputAs
        - gmail_send: Send email via Gmail API. Fields: to, subject, body, executionType="cloud"
        - gmail_search: Search Gmail inbox. Fields: query, outputAs, executionType="cloud"
        - sheets_append: Append row to Google Sheet. Fields: spreadsheetId, range, values, executionType="cloud"
        - sheets_read: Read range from Google Sheet. Fields: spreadsheetId, range, outputAs, executionType="cloud"

        Trigger types:
        - "schedule": Runs on cron (e.g., "0 9 * * 1-5" for weekday 9am). Fields: cron
        - "event": Runs when a condition is met (e.g., "file_added", "email_received"). Fields: event
        - "manual": Runs only when triggered by user

        exportTargets: Array of platforms this workflow could be exported to: ["local", "n8n", "zapier"]

        Workflow JSON Schema:
        {
          "name": "string (concise, verb-based, e.g., 'Send Daily Sales Report')",
          "trigger": {
            "type": "schedule|event|manual",
            "cron": "5-field cron string or null",
            "description": "Human-readable schedule description",
            "event": "event type or null"
          },
          "steps": [
            {
              "id": "step1",
              "action": "action_type from list above",
              "description": "Plain English description",
              "enabled": true,
              "requiresReview": false,
              "url": "string|null",
              "selector": "string|null",
              "output": "string|null",
              "file": "string|null",
              "data": "string|null",
              "template": "string|null",
              "recipients": "string|null",
              "appName": "string|null",
              "inputFrom": "step_id|null (which step's output to use as input)",
              "outputAs": "string|null (variable name for this step's output)",
              "condition": "string|null",
              "method": "GET|POST|PUT|DELETE|null",
              "headers": {"key": "value"}|null,
              "body": "string|null",
              "path": "string|null",
              "encoding": "utf8|base64|null",
              "extractPattern": "regex or CSS selector|null",
              "transform": "jq expression or template|null",
              "duration": seconds|null,
              "shortcut": "cmd+s style shortcut|null",
              "to": "string or {{variable}}|null",
              "subject": "string or {{variable}}|null",
              "query": "Gmail search syntax|null",
              "spreadsheetId": "string or {{variable}}|null",
              "range": "e.g. Sheet1!A:Z|null",
              "values": ["string or {{variable}}", "..."]|null,
              "executionType": "cloud|local"
            }
          ],
          "confidence": 0.0-1.0,
          "requiresReview": ["step_id: reason"],
          "scheduleRecommendation": "human-readable suggestion|null",
          "exportTargets": ["local", "n8n", "zapier"]
        }
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