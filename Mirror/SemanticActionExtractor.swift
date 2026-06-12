import Foundation

// MARK: - Canonical Semantic Action Model

struct SemanticAction: Codable {
    let id: String
    let action: String          // e.g. "SearchEmail", "OpenURL", "AppendSpreadsheetRow"
    let provider: String        // e.g. "gmail", "sheets", "chrome", "generic"
    let description: String
    var confidence: Double      // 0.0 - 1.0
    var inputSources: [String]  // data flow: where input comes from
    var outputKey: String?      // variable name for downstream steps

    // Action-specific payload
    let payload: Payload

    // Metadata for execution engine
    let executionType: String   // "cloud" | "local"
    let requiresReview: Bool

    struct Payload: Codable {
        var url: String?
        var appName: String?
        var typedText: String?
        var extractedValue: String?
        var to: String?
        var subject: String?
        var body: String?
        var query: String?
        var spreadsheetId: String?
        var range: String?
        var values: [String]?
        var formFields: [String: String]?
        var filePath: String?
        var fileName: String?
        var clickX: Double?
        var clickY: Double?
        var durationSeconds: Double?

        init(url: String? = nil, appName: String? = nil, typedText: String? = nil,
             extractedValue: String? = nil, to: String? = nil, subject: String? = nil,
             body: String? = nil, query: String? = nil, spreadsheetId: String? = nil,
             range: String? = nil, values: [String]? = nil, formFields: [String: String]? = nil,
             filePath: String? = nil, fileName: String? = nil,
             clickX: Double? = nil, clickY: Double? = nil, durationSeconds: Double? = nil) {
            self.url = url
            self.appName = appName
            self.typedText = typedText
            self.extractedValue = extractedValue
            self.to = to
            self.subject = subject
            self.body = body
            self.query = query
            self.spreadsheetId = spreadsheetId
            self.range = range
            self.values = values
            self.formFields = formFields
            self.filePath = filePath
            self.fileName = fileName
            self.clickX = clickX
            self.clickY = clickY
            self.durationSeconds = durationSeconds
        }
    }
}

// MARK: - Event Grouper: raw events → logical action boundaries

struct ActionCandidate {
    let events: [EventTapManager.CapturedEvent]
    let dominantApp: String
    let activeURL: String?
    let timeWindow: (start: Double, end: Double)
    let typedBuffer: String
    let clickTargets: [(x: Double, y: Double)]
    let hasClipboardChange: Bool
    let clipboardContents: String?
    let appSwitchEvents: [String]
}

struct SemanticActionExtractor {

    // MARK: - Step 1: Group raw events into action candidates

    static func groupEvents(_ events: [EventTapManager.CapturedEvent]) -> [ActionCandidate] {
        guard !events.isEmpty else { return [] }

        // Split events when user switches apps or there's a significant time gap (>3s idle)
        let maxIdleGap: Double = 3.0
        var candidates: [ActionCandidate] = []
        var currentEvents: [EventTapManager.CapturedEvent] = []
        var currentApp = events[0].targetApp ?? "Unknown"
        var currentURL = events[0].targetURL
        var typedBuffer = ""
        var clickTargets: [(x: Double, y: Double)] = []
        var hasClipboardChange = false
        var clipboardContents: String? = nil
        var appSwitches: [String] = [currentApp]
        var lastEventTime = events[0].timestamp

        func flushCandidate() {
            guard !currentEvents.isEmpty else { return }
            let candidate = ActionCandidate(
                events: currentEvents,
                dominantApp: currentApp,
                activeURL: currentURL,
                timeWindow: (start: currentEvents.first!.timestamp, end: currentEvents.last!.timestamp),
                typedBuffer: typedBuffer.trimmingCharacters(in: .whitespaces),
                clickTargets: clickTargets,
                hasClipboardChange: hasClipboardChange,
                clipboardContents: clipboardContents,
                appSwitchEvents: appSwitches
            )
            candidates.append(candidate)
            currentEvents = []
            typedBuffer = ""
            clickTargets = []
            hasClipboardChange = false
            clipboardContents = nil
            appSwitches = [currentApp]
        }

        for event in events {
            let app = event.targetApp ?? "Unknown"
            let timeSinceLast = event.timestamp - lastEventTime

            // New candidate boundary: app switch or long idle gap
            if app != currentApp || timeSinceLast > maxIdleGap {
                flushCandidate()
                currentApp = app
                currentURL = event.targetURL
            }

            if app != currentApp || (appSwitches.last != app) {
                appSwitches.append(app)
            }

            if let url = event.targetURL, !url.isEmpty {
                currentURL = url
            }

            currentEvents.append(event)
            lastEventTime = event.timestamp

            switch event.type {
            case "keyDown":
                if let chars = event.characters, event.redacted != true {
                    typedBuffer += chars
                }
            case "mouseDown", "rightMouseDown":
                if let pos = event.position {
                    clickTargets.append((x: pos["x"] ?? 0, y: pos["y"] ?? 0))
                }
            case "clipboardChange":
                hasClipboardChange = true
                clipboardContents = event.clipboardSnapshot
            default:
                break
            }
        }
        flushCandidate()
        return candidates
    }

    // MARK: - Step 2: Provider detection from URL / app name

    enum DetectedProvider {
        case gmail, googleSheets, googleDrive, googleCalendar
        case slack, notion
        case genericBrowser(chrome: Bool)
        case genericApp(String)

        var name: String {
            switch self {
            case .gmail: return "gmail"
            case .googleSheets: return "sheets"
            case .googleDrive: return "drive"
            case .googleCalendar: return "calendar"
            case .slack: return "slack"
            case .notion: return "notion"
            case .genericBrowser: return "browser"
            case .genericApp(let name): return name
            }
        }
    }

    static func detectProvider(app: String, url: String?) -> DetectedProvider {
        let urlStr = url?.lowercased() ?? ""
        let appLower = app.lowercased()

        // Google apps via URL
        if urlStr.contains("mail.google.com") || urlStr.contains("gmail.com") {
            return .gmail
        }
        if urlStr.contains("docs.google.com/spreadsheets") {
            return .googleSheets
        }
        if urlStr.contains("docs.google.com/document") {
            return .googleDrive
        }
        if urlStr.contains("calendar.google.com") {
            return .googleCalendar
        }
        if urlStr.contains("drive.google.com") {
            return .googleDrive
        }

        // Google apps via app name (Chrome showing Google sites)
        if appLower.contains("chrome") || appLower.contains("safari") || appLower.contains("arc") {
            let isChrome = appLower.contains("chrome")
            if urlStr.contains("google.com") {
                // Sub-detect from page title patterns — best effort
                return .genericBrowser(chrome: isChrome)
            }
            return .genericBrowser(chrome: isChrome)
        }

        // Slack
        if appLower.contains("slack") || urlStr.contains("slack.com") {
            return .slack
        }

        // Notion
        if appLower.contains("notion") || urlStr.contains("notion.so") {
            return .notion
        }

        return .genericApp(app)
    }

    // MARK: - Step 3: Extract semantic actions from candidates

    static func extractActions(from candidates: [ActionCandidate]) -> [SemanticAction] {
        var actions: [SemanticAction] = []
        var stepCounter = 0

        for candidate in candidates {
            let provider = detectProvider(app: candidate.dominantApp, url: candidate.activeURL)

            switch provider {
            case .gmail:
                actions += extractGmailActions(from: candidate, stepCounter: &stepCounter)
            case .googleSheets:
                actions += extractSheetsActions(from: candidate, stepCounter: &stepCounter)
            case .genericBrowser, .genericApp:
                actions += extractGenericActions(from: candidate, stepCounter: &stepCounter)
            case .slack, .notion:
                actions += extractGenericActions(from: candidate, stepCounter: &stepCounter)
            default:
                actions += extractGenericActions(from: candidate, stepCounter: &stepCounter)
            }
        }

        // Deduplicate: merge consecutive actions of same type on same target
        actions = deduplicate(actions)

        // Link data flows: if Action N copies text and Action N+1 pastes it
        actions = linkDataFlows(actions)

        return actions
    }

    // MARK: - Gmail Action Extraction

    private static func extractGmailActions(from candidate: ActionCandidate, stepCounter: inout Int) -> [SemanticAction] {
        var actions: [SemanticAction] = []
        let text = candidate.typedBuffer.lowercased()

        // Detect Gmail search: typing into search box
        if text.contains("in:") || text.contains("from:") || text.contains("subject:") ||
           isGmailSearchPattern(text, events: candidate.events) {
            stepCounter += 1
            actions.append(SemanticAction(
                id: "step\(stepCounter)",
                action: "gmail_search",
                provider: "gmail",
                description: "Search Gmail for '\(candidate.typedBuffer)'",
                confidence: 0.88,
                inputSources: [],
                outputKey: "gmail_search_results",
                payload: SemanticAction.Payload(query: candidate.typedBuffer),
                executionType: "cloud",
                requiresReview: false
            ))
            return actions
        }

        // Detect Gmail compose: long typing with subject line
        if text.count > 30 && candidate.typedBuffer.contains("\n") {
            stepCounter += 1
            let (to, subject, body) = parseEmailCompose(candidate.typedBuffer)
            actions.append(SemanticAction(
                id: "step\(stepCounter)",
                action: "gmail_send",
                provider: "gmail",
                description: body.isEmpty ? "Compose email to \(to)" : "Send email to \(to) with subject '\(subject)'",
                confidence: 0.85,
                inputSources: [],
                outputKey: nil,
                payload: SemanticAction.Payload(to: to, subject: subject, body: body),
                executionType: "cloud",
                requiresReview: to.isEmpty
            ))
            return actions
        }

        // Detect clicking an email in inbox → opening it
        if candidate.clickTargets.count >= 2 && !text.isEmpty && text.count < 50 {
            stepCounter += 1
            actions.append(SemanticAction(
                id: "step\(stepCounter)",
                action: "gmail_open_email",
                provider: "gmail",
                description: "Open email matching '\(candidate.typedBuffer)'",
                confidence: 0.72,
                inputSources: [],
                outputKey: "opened_email",
                payload: SemanticAction.Payload(query: candidate.typedBuffer),
                executionType: "local",
                requiresReview: true
            ))
            return actions
        }

        return extractGenericActions(from: candidate, stepCounter: &stepCounter)
    }

    private static func isGmailSearchPattern(_ text: String, events: [EventTapManager.CapturedEvent]) -> Bool {
        // Heuristic: rapid typing of 3-30 chars in Gmail with no commas/periods = likely search
        guard text.count >= 3 && text.count <= 30 else { return false }
        let hasPunctuation = text.contains(where: { ",.!?".contains($0) })
        return !hasPunctuation
    }

    private static func parseEmailCompose(_ text: String) -> (to: String, subject: String, body: String) {
        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        if lines.count >= 2 {
            let to = lines[0].contains("@") ? lines[0] : ""
            let subject = lines.count >= 2 ? lines[1] : ""
            let body = lines.count >= 3 ? lines.dropFirst(2).joined(separator: "\n") : ""
            return (to, subject, body)
        }
        return ("", text, "")
    }

    // MARK: - Google Sheets Action Extraction

    private static func extractSheetsActions(from candidate: ActionCandidate, stepCounter: inout Int) -> [SemanticAction] {
        var actions: [SemanticAction] = []

        // Detect append row: typing values then Enter or Tab between cells
        if candidate.typedBuffer.count > 3 {
            let spreadsheetId = SheetsConnector.extractSpreadsheetId(from: candidate.activeURL ?? "") ?? "{{from_url}}"
            // Split typed text by common cell delimiters: tab or comma
            let values = candidate.typedBuffer
                .components(separatedBy: "\t")
                .filter { !$0.isEmpty }
                .flatMap { $0.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) } }

            stepCounter += 1
            actions.append(SemanticAction(
                id: "step\(stepCounter)",
                action: "sheets_append",
                provider: "sheets",
                description: "Append row to sheet: \(values.joined(separator: ", "))",
                confidence: 0.82,
                inputSources: [],
                outputKey: nil,
                payload: SemanticAction.Payload(
                    spreadsheetId: spreadsheetId,
                    range: "Sheet1!A:Z",
                    values: values
                ),
                executionType: "cloud",
                requiresReview: false
            ))
            return actions
        }

        // Detect reading data from sheet: copy from clipboard
        if candidate.hasClipboardChange, let clip = candidate.clipboardContents, clip.count > 10 {
            let spreadsheetId = SheetsConnector.extractSpreadsheetId(from: candidate.activeURL ?? "") ?? ""
            stepCounter += 1
            actions.append(SemanticAction(
                id: "step\(stepCounter)",
                action: "sheets_read",
                provider: "sheets",
                description: "Read data from spreadsheet",
                confidence: 0.76,
                inputSources: [],
                outputKey: "sheet_data",
                payload: SemanticAction.Payload(
                    spreadsheetId: spreadsheetId,
                    range: "Sheet1!A:Z"
                ),
                executionType: "cloud",
                requiresReview: true
            ))
            return actions
        }

        return extractGenericActions(from: candidate, stepCounter: &stepCounter)
    }

    // MARK: - Generic Action Extraction (fallback for unrecognized apps)

    private static func extractGenericActions(from candidate: ActionCandidate, stepCounter: inout Int) -> [SemanticAction] {
        var actions: [SemanticAction] = []

        // URL navigation
        if let url = candidate.activeURL, let detected = URL(string: url), detected.host != nil {
            stepCounter += 1
            actions.append(SemanticAction(
                id: "step\(stepCounter)",
                action: "open_url",
                provider: "browser",
                description: "Navigate to \(detected.host ?? url)",
                confidence: 0.95,
                inputSources: [],
                outputKey: nil,
                payload: SemanticAction.Payload(url: url),
                executionType: "local",
                requiresReview: false
            ))
        }

        // Typed text (>5 chars) → likely form fill or type_text
        if candidate.typedBuffer.count > 5 {
            stepCounter += 1
            let isLikelyForm = candidate.typedBuffer.count > 20 && candidate.typedBuffer.count < 300
            actions.append(SemanticAction(
                id: "step\(stepCounter)",
                action: isLikelyForm ? "fill_form" : "type_text",
                provider: candidate.dominantApp,
                description: isLikelyForm ? "Fill form with \(candidate.typedBuffer.prefix(40))..." : "Type '\(candidate.typedBuffer)'",
                confidence: isLikelyForm ? 0.65 : 0.78,
                inputSources: [],
                outputKey: nil,
                payload: SemanticAction.Payload(typedText: candidate.typedBuffer),
                executionType: "local",
                requiresReview: isLikelyForm
            ))
        }

        // Clipboard copy
        if candidate.hasClipboardChange, let clip = candidate.clipboardContents, !clip.isEmpty {
            stepCounter += 1
            actions.append(SemanticAction(
                id: "step\(stepCounter)",
                action: "extract_data",
                provider: "clipboard",
                description: "Copy data to clipboard",
                confidence: 0.90,
                inputSources: [],
                outputKey: "clipboard_data",
                payload: SemanticAction.Payload(extractedValue: clip),
                executionType: "local",
                requiresReview: false
            ))
        }

        // Click actions
        if !candidate.clickTargets.isEmpty && candidate.typedBuffer.isEmpty && !candidate.hasClipboardChange {
            stepCounter += 1
            let target = candidate.clickTargets.first!
            actions.append(SemanticAction(
                id: "step\(stepCounter)",
                action: "click",
                provider: candidate.dominantApp,
                description: "Click at (\(Int(target.x)), \(Int(target.y)))",
                confidence: 0.40,
                inputSources: [],
                outputKey: nil,
                payload: SemanticAction.Payload(clickX: target.x, clickY: target.y),
                executionType: "local",
                requiresReview: true
            ))
        }

        return actions
    }

    // MARK: - Step 4: Deduplication

    private static func deduplicate(_ actions: [SemanticAction]) -> [SemanticAction] {
        guard actions.count > 1 else { return actions }
        var result: [SemanticAction] = [actions[0]]
        for i in 1..<actions.count {
            let prev = result.last!
            let curr = actions[i]
            // Merge consecutive identical actions on same target
            if prev.action == curr.action && prev.provider == curr.provider &&
               prev.payload.url == curr.payload.url {
                continue
            }
            result.append(curr)
        }
        return result
    }

    // MARK: - Step 5: Data flow linking

    private static func linkDataFlows(_ actions: [SemanticAction]) -> [SemanticAction] {
        var result = actions
        for i in 1..<result.count {
            // If previous action produced a clipboard copy and current action types text,
            // link them via inputSources
            if result[i - 1].action == "extract_data",
               result[i].action == "type_text" || result[i].action == "fill_form",
               let key = result[i - 1].outputKey {
                result[i].inputSources.append(key)
                result[i].confidence += 0.05 // slight boost for data flow
            }
        }
        return result
    }

    // MARK: - Step 6: Structured JSON output

    static func toJSON(_ actions: [SemanticAction]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(actions),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    // MARK: - Full Pipeline (convenience)

    static func extract(from events: [EventTapManager.CapturedEvent]) -> [SemanticAction] {
        let candidates = groupEvents(events)
        return extractActions(from: candidates)
    }

    // MARK: - Context Summary for AI Prompt

    /// Generate a structured summary that the AI analysis prompt can use
    /// alongside the raw event timeline for better accuracy.
    static func buildContextSummary(from events: [EventTapManager.CapturedEvent]) -> String {
        let actions = extract(from: events)
        guard !actions.isEmpty else { return "" }

        var lines: [String] = ["## Semantic Context (pre-extracted)"]
        lines.append("The following actions were detected heuristically. Use these to verify and refine your own analysis.\n")

        for action in actions {
            let badge = action.executionType == "cloud" ? "☁" : "💻"
            let conf = Int(action.confidence * 100)
            lines.append("- \(badge) **\(action.action)** (\(action.provider)) — \(action.description) [confidence: \(conf)%]")
            if !action.inputSources.isEmpty {
                lines.append("  Input from: \(action.inputSources.joined(separator: ", "))")
            }
            if let key = action.outputKey {
                lines.append("  Output as: {{\(key)}}")
            }
        }

        lines.append("\n---")
        return lines.joined(separator: "\n")
    }
}

