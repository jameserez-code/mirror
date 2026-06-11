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
              "shortcut": "cmd+s style shortcut|null"
            }
          ],
          "confidence": 0.0-1.0,
          "requiresReview": ["step_id: reason"],
          "scheduleRecommendation": "human-readable suggestion|null",
          "exportTargets": ["local", "n8n", "zapier"]
        }
        """

    // MARK: - User Prompt Builder

    static func buildUserPrompt(timeline: String, metadata: [String: Any]) -> String {
        let duration = (metadata["duration"] as? Double) ?? 0
        let eventCount = (metadata["eventCount"] as? Int) ?? 0
        return """
            Activity Log:
            Duration: \(String(format: "%.1f", duration))s | Events: \(eventCount)

            \(timeline)

            Analyze this recording and output the workflow JSON. Focus on the repeatable pattern, use semantic actions, and add data flow between steps using inputFrom/outputAs.
            """
    }

    // MARK: - API Call

    @discardableResult
    static func analyze(events: [EventTapManager.CapturedEvent],
                        sessionId: String,
                        metadata: [String: Any],
                        completion: @escaping (Result<Workflow, AnalysisError>) -> Void) -> URLSessionDataTask? {
        let sessionDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Mirror/Sessions/\(sessionId)")

        let timeline: String
        if FileManager.default.fileExists(atPath: sessionDir.appendingPathComponent("events.json").path) {
            timeline = SessionPackager.shared.buildRichActivityTimeline(events: events, sessionDir: sessionDir)
        } else {
            timeline = SessionPackager.shared.buildActivityTimeline(events: events)
        }

        let userPrompt = buildUserPrompt(timeline: timeline, metadata: metadata)

        let provider = Settings.apiProvider
        switch provider {
        case "anthropic":
            return analyzeWithAnthropic(systemPrompt: systemPrompt, userPrompt: userPrompt, completion: completion)
        case "openai":
            return analyzeWithOpenAI(systemPrompt: systemPrompt, userPrompt: userPrompt, completion: completion)
        case "openrouter":
            return analyzeWithOpenRouter(systemPrompt: systemPrompt, userPrompt: userPrompt, completion: completion)
        default:
            return analyzeWithOpenRouter(systemPrompt: systemPrompt, userPrompt: userPrompt, completion: completion)
        }
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

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
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

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
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

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
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