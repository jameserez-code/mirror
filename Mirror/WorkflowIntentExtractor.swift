import Foundation

// MARK: - Artifact Models

struct ExtractedArtifact: Codable {
    let id: String
    let artifactType: String         // "invoice_tracker", "lead_list", "email_thread", "report", etc.
    let domain: String               // "accounts_payable", "lead_generation", "reporting", etc.
    let sourceApp: String            // e.g. "gmail", "sheets", "chrome"
    let title: String                // human-readable name
    let fields: [ArtifactField]      // detected structured fields
    let textContent: String?         // extracted text (truncated)
    let url: String?                 // source URL if web-based
    let confidence: Double           // 0.0 - 1.0
    var relationships: [ArtifactRelationship] // links to other artifacts (mutable for linking)

    struct ArtifactField: Codable {
        let name: String             // e.g. "vendor", "amount", "due_date"
        let value: String
        let detectedFrom: String     // "clipboard", "typed_text", "ocr", "page_title"
    }

    struct ArtifactRelationship: Codable {
        let targetArtifactId: String
        let relationship: String     // "derived_from", "updates", "references", "contains"
    }
}

// MARK: - Workflow Intent Model

struct WorkflowIntent: Codable {
    let objective: String            // e.g. "maintain_accounts_payable_tracker"
    let domain: String               // business domain
    let description: String          // plain-English explanation
    let confidence: Double           // 0.0 - 1.0
    let triggerPattern: String       // cron recommendation
    let frequency: String            // "hourly", "daily", "weekly", "monthly", "on_demand"
    let estimatedDuration: Double    // seconds
}

// MARK: - Workflow Plan Model

struct WorkflowPlan: Codable {
    let objective: String
    let domain: String
    let confidence: ConfidenceBreakdown
    let artifacts: [ExtractedArtifact]
    let intent: WorkflowIntent
    let requiredIntegrations: [IntegrationRequirement]
    let steps: [PlanStep]
    let executionStrategy: ExecutionStrategy
    let automationReadiness: AutomationReadiness

    struct ConfidenceBreakdown: Codable {
        let overallConfidence: Double
        let actionConfidence: Double     // avg of individual action confidences
        let artifactConfidence: Double   // avg of artifact extraction confidence
        let coherenceConfidence: Double  // how well actions + artifacts fit the objective
        let objectiveConfidence: Double   // how certain we are about the objective
    }

    struct IntegrationRequirement: Codable {
        let provider: String         // "gmail", "sheets", "drive", "slack", "notion"
        let reason: String           // why this integration is needed
        let isConnected: Bool        // whether OAuth is already set up
        let requiredScopes: [String] // API scopes needed
    }

    struct PlanStep: Codable {
        let order: Int
        let semanticActionId: String // references the SemanticAction id
        let description: String
        let executionType: String    // "cloud" | "local" | "hybrid"
        let provider: String
        let requiresReview: Bool
    }

    struct ExecutionStrategy: Codable {
        let primaryMode: String      // "cloud_preferred" | "local_preferred" | "hybrid"
        let cloudFeasible: Bool      // can this run fully in cloud?
        let cloudBlockers: [String]  // steps that prevent full cloud execution
        let fallbackMode: String     // what to do if cloud execution fails
    }

    struct AutomationReadiness: Codable {
        let isReady: Bool            // can this be deployed right now?
        let blockers: [String]       // what's preventing deployment
        let recommendations: [String] // what to fix
    }
}

// MARK: - Workflow Template (pattern for intent matching)

struct WorkflowTemplate {
    let objective: String
    let domain: String
    let description: String
    let triggerPattern: String       // recommended cron
    let frequency: String
    let actionSequence: [String]     // ordered action types that match this template
    let requiredArtifacts: [String]  // artifact types needed
    let providerPreferences: [String: String] // provider → execution mode
    let keywordTriggers: [String]    // keywords that signal this domain
    let baseConfidence: Double       // starting confidence before evidence
}

// MARK: - Workflow Intent Extractor

struct WorkflowIntentExtractor {

    // MARK: - Step 1: Artifact Extraction

    static func extractArtifacts(
        from actions: [SemanticAction],
        events: [EventTapManager.CapturedEvent],
        sessionDir: URL? = nil
    ) -> [ExtractedArtifact] {
        var artifacts: [ExtractedArtifact] = []
        var artifactId = 0

        // Collect all text snippets from the session: URLs, clipboard, typed text, window titles
        let sessionContext = buildSessionContext(events: events)

        // --- Spreadsheet artifacts ---
        for action in actions where action.provider == "sheets" {
            artifactId += 1
            let artifact = extractSpreadsheetArtifact(
                id: "artifact\(artifactId)",
                action: action,
                context: sessionContext
            )
            if artifact != nil { artifacts.append(artifact!) }
        }

        // --- Email artifacts ---
        for action in actions where action.provider == "gmail" {
            artifactId += 1
            let artifact = extractEmailArtifact(
                id: "artifact\(artifactId)",
                action: action,
                context: sessionContext
            )
            if artifact != nil { artifacts.append(artifact!) }
        }

        // --- Clipboard / file artifacts ---
        if let clipContent = sessionContext.allClipboardContent.first(where: { $0.count > 20 }) {
            artifactId += 1
            if let artifact = extractClipboardArtifact(id: "artifact\(artifactId)", content: clipContent, context: sessionContext) {
                artifacts.append(artifact)
            }
        }

        // --- Web page artifacts ---
        for url in sessionContext.visitedURLs {
            artifactId += 1
            if let artifact = extractWebPageArtifact(id: "artifact\(artifactId)", url: url, context: sessionContext) {
                artifacts.append(artifact)
            }
        }

        // Link related artifacts
        artifacts = linkArtifacts(artifacts)

        return artifacts
    }

    // MARK: - Artifact Sub-Extractors

    private static func extractSpreadsheetArtifact(
        id: String, action: SemanticAction, context: SessionContext
    ) -> ExtractedArtifact? {
        let fields = detectSpreadsheetFields(from: context)
        guard !fields.isEmpty else { return nil }

        let (artifactType, domain) = classifySpreadsheet(fields: fields, context: context)

        return ExtractedArtifact(
            id: id,
            artifactType: artifactType,
            domain: domain,
            sourceApp: "sheets",
            title: action.payload.spreadsheetId ?? "Untitled Sheet",
            fields: fields,
            textContent: context.combinedText(limit: 500),
            url: context.visitedURLs.first(where: { $0.contains("spreadsheets") }),
            confidence: fields.count >= 3 ? 0.85 : 0.60,
            relationships: []
        )
    }

    private static func extractEmailArtifact(
        id: String, action: SemanticAction, context: SessionContext
    ) -> ExtractedArtifact? {
        var fields: [ExtractedArtifact.ArtifactField] = []

        if let subject = action.payload.subject, !subject.isEmpty {
            fields.append(.init(name: "subject", value: subject, detectedFrom: "typed_text"))
        }
        if let to = action.payload.to, !to.isEmpty {
            fields.append(.init(name: "recipient", value: to, detectedFrom: "typed_text"))
        }
        if let query = action.payload.query, !query.isEmpty {
            fields.append(.init(name: "search_query", value: query, detectedFrom: "typed_text"))
        }

        guard !fields.isEmpty else { return nil }

        let (artifactType, domain) = classifyEmail(fields: fields, action: action, context: context)

        return ExtractedArtifact(
            id: id,
            artifactType: artifactType,
            domain: domain,
            sourceApp: "gmail",
            title: fields.first(where: { $0.name == "subject" })?.value ?? "Email",
            fields: fields,
            textContent: action.payload.body,
            url: nil,
            confidence: 0.78,
            relationships: []
        )
    }

    private static func extractClipboardArtifact(
        id: String, content: String, context: SessionContext
    ) -> ExtractedArtifact? {
        let fields = detectStructuredFields(from: content)
        guard !fields.isEmpty else { return nil }

        let (artifactType, domain) = classifyClipboardData(fields: fields, context: context)

        return ExtractedArtifact(
            id: id,
            artifactType: artifactType,
            domain: domain,
            sourceApp: "clipboard",
            title: "Copied Data",
            fields: fields,
            textContent: String(content.prefix(500)),
            url: nil,
            confidence: fields.count >= 2 ? 0.72 : 0.50,
            relationships: []
        )
    }

    private static func extractWebPageArtifact(
        id: String, url: String, context: SessionContext
    ) -> ExtractedArtifact? {
        let fields = detectWebPageFields(url: url, context: context)

        let (artifactType, domain) = classifyWebPage(url: url, fields: fields, context: context)

        return ExtractedArtifact(
            id: id,
            artifactType: artifactType,
            domain: domain,
            sourceApp: "browser",
            title: extractPageTitle(from: url) ?? url,
            fields: fields,
            textContent: nil,
            url: url,
            confidence: 0.70,
            relationships: []
        )
    }

    // MARK: - Field Detection Heuristics

    private static func detectSpreadsheetFields(from context: SessionContext) -> [ExtractedArtifact.ArtifactField] {
        var fields: [ExtractedArtifact.ArtifactField] = []

        // Analyze all typed text looking for tabular data
        for text in context.allTypedText where text.contains("\t") || text.contains(",") {
            let parts = text.components(separatedBy: CharacterSet(charactersIn: "\t,"))
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if parts.count >= 2 {
                // Try to match common column patterns
                for part in parts {
                    if let field = classifyCellValue(part) {
                        fields.append(field)
                    }
                }
            }
        }

        return fields
    }

    private static func classifyCellValue(_ value: String) -> ExtractedArtifact.ArtifactField? {
        let lower = value.lowercased()

        // Amount patterns
        if let amount = extractAmount(value) {
            return .init(name: "amount", value: amount, detectedFrom: "clipboard")
        }

        // Date patterns
        if let date = extractDate(value) {
            return .init(name: "date", value: date, detectedFrom: "clipboard")
        }

        // Email
        if value.contains("@") && value.contains(".") {
            return .init(name: "email", value: value, detectedFrom: "clipboard")
        }

        // URL
        if value.hasPrefix("http") {
            return .init(name: "url", value: value, detectedFrom: "clipboard")
        }

        // Named entity (proper noun)
        if value.count > 2 && value.first?.isUppercase == true {
            return .init(name: "name", value: value, detectedFrom: "clipboard")
        }

        // Description text
        if value.count > 10 && !lower.contains("http") {
            return .init(name: "description", value: value, detectedFrom: "clipboard")
        }

        return nil
    }

    private static func extractAmount(_ value: String) -> String? {
        let pattern = #"\$?\d+[.,]\d{2}"#
        if let range = value.range(of: pattern, options: .regularExpression) {
            return String(value[range])
        }
        return nil
    }

    private static func extractDate(_ value: String) -> String? {
        let patterns = [
            #"\d{1,2}/\d{1,2}/\d{2,4}"#,
            #"\d{4}-\d{2}-\d{2}"#,
            #"\d{1,2}\.\d{1,2}\.\d{2,4}"#
        ]
        for pattern in patterns {
            if let range = value.range(of: pattern, options: .regularExpression) {
                return String(value[range])
            }
        }
        return nil
    }

    private static func detectStructuredFields(from text: String) -> [ExtractedArtifact.ArtifactField] {
        var fields: [ExtractedArtifact.ArtifactField] = []

        // Split by common delimiters
        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        for line in lines {
            // Try tab-separated
            let tabs = line.components(separatedBy: "\t")
            if tabs.count >= 2 {
                for value in tabs.map({ $0.trimmingCharacters(in: .whitespaces) }) where !value.isEmpty {
                    if let field = classifyCellValue(value) {
                        fields.append(field)
                    }
                }
                continue
            }

            // Try key:value or key=value
            if let colonRange = line.range(of: ":") {
                let key = String(line[..<colonRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                let value = String(line[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !key.isEmpty && !value.isEmpty {
                    fields.append(.init(name: key.lowercased(), value: value, detectedFrom: "clipboard"))
                }
            }
        }

        return fields
    }

    private static func detectWebPageFields(url: String, context: SessionContext) -> [ExtractedArtifact.ArtifactField] {
        var fields: [ExtractedArtifact.ArtifactField] = []

        // Extract domain
        if let host = URL(string: url)?.host {
            fields.append(.init(name: "domain", value: host, detectedFrom: "url"))
        }

        // Check for common platforms
        if url.contains("linkedin.com") {
            fields.append(.init(name: "platform", value: "linkedin", detectedFrom: "url"))
        } else if url.contains("stripe.com") {
            fields.append(.init(name: "platform", value: "stripe", detectedFrom: "url"))
        } else if url.contains("notion.so") {
            fields.append(.init(name: "platform", value: "notion", detectedFrom: "url"))
        }

        return fields
    }

    // MARK: - Artifact Classification

    private static func classifySpreadsheet(
        fields: [ExtractedArtifact.ArtifactField], context: SessionContext
    ) -> (artifactType: String, domain: String) {
        let fieldNames = Set(fields.map { $0.name })
        let allText = context.combinedText(limit: 1000).lowercased()

        // Invoice tracker: amount + date + vendor/name
        if fieldNames.contains("amount") && fieldNames.contains("date") {
            if allText.contains("invoice") || allText.contains("bill") || allText.contains("vendor") {
                return ("invoice_tracker", "accounts_payable")
            }
            if allText.contains("receipt") || allText.contains("expense") {
                return ("expense_tracker", "expense_management")
            }
            return ("financial_tracker", "finance")
        }

        // Lead list: email + name + company
        if fieldNames.contains("email") && fieldNames.contains("name") {
            return ("lead_list", "lead_generation")
        }

        // Contact list: email + name (no company)
        if fieldNames.contains("email") {
            return ("contact_list", "crm")
        }

        // Report
        if allText.contains("report") || allText.contains("weekly") || allText.contains("monthly") {
            return ("report", "reporting")
        }

        return ("spreadsheet", "general")
    }

    private static func classifyEmail(
        fields: [ExtractedArtifact.ArtifactField], action: SemanticAction, context: SessionContext
    ) -> (artifactType: String, domain: String) {
        let allText = (action.payload.subject ?? "") + " " + (action.payload.body ?? "")
        let lower = allText.lowercased()

        if lower.contains("invoice") || lower.contains("payment") || lower.contains("bill") {
            return ("invoice_email", "accounts_payable")
        }
        if lower.contains("receipt") || lower.contains("expense") {
            return ("receipt_email", "expense_management")
        }
        if lower.contains("report") || lower.contains("weekly") || lower.contains("digest") {
            return ("report_email", "reporting")
        }
        if lower.contains("newsletter") || lower.contains("marketing") {
            return ("marketing_email", "marketing")
        }

        return ("email", "general")
    }

    private static func classifyClipboardData(
        fields: [ExtractedArtifact.ArtifactField], context: SessionContext
    ) -> (artifactType: String, domain: String) {
        let fieldNames = Set(fields.map { $0.name })

        if fieldNames.contains("amount") {
            return ("financial_data", "finance")
        }
        if fieldNames.contains("email") {
            return ("contact_data", "crm")
        }

        return ("structured_data", "general")
    }

    private static func classifyWebPage(
        url: String, fields: [ExtractedArtifact.ArtifactField], context: SessionContext
    ) -> (artifactType: String, domain: String) {
        let lower = url.lowercased()

        if lower.contains("linkedin.com") {
            return ("linkedin_profile", "lead_generation")
        }
        if lower.contains("stripe.com") || lower.contains("dashboard") {
            return ("payment_dashboard", "finance")
        }
        if lower.contains("docs.google.com/spreadsheets") {
            return ("google_sheet", "general")
        }
        if lower.contains("docs.google.com/document") {
            return ("google_doc", "general")
        }

        return ("web_page", "general")
    }

    private static func extractPageTitle(from url: String) -> String? {
        guard let host = URL(string: url)?.host else { return nil }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    // MARK: - Artifact Linking

    private static func linkArtifacts(_ artifacts: [ExtractedArtifact]) -> [ExtractedArtifact] {
        var result = artifacts

        for i in 0..<result.count {
            for j in (i + 1)..<result.count {
                let a = result[i], b = result[j]

                // Same domain → related
                if a.domain == b.domain && a.id != b.id {
                    result[i].relationships.append(.init(targetArtifactId: b.id, relationship: "related"))
                    result[j].relationships.append(.init(targetArtifactId: a.id, relationship: "related"))
                }

                // Email → spreadsheet (invoice email feeding tracker)
                if a.sourceApp == "gmail" && b.sourceApp == "sheets" && a.domain == b.domain {
                    result[i].relationships.append(.init(targetArtifactId: b.id, relationship: "updates"))
                }

                // Clipboard → spreadsheet (copied data pasted into sheet)
                if a.sourceApp == "clipboard" && b.sourceApp == "sheets" {
                    result[i].relationships.append(.init(targetArtifactId: b.id, relationship: "derived_from"))
                }
            }
        }

        return result
    }

    // MARK: - Step 2: Workflow Intent Inference

    static func inferIntent(
        actions: [SemanticAction],
        artifacts: [ExtractedArtifact]
    ) -> WorkflowIntent {
        let templates = buildWorkflowTemplates()

        var bestMatch: WorkflowTemplate?
        var bestScore: Double = 0

        for template in templates {
            let score = scoreTemplateMatch(template: template, actions: actions, artifacts: artifacts)
            if score > bestScore {
                bestScore = score
                bestMatch = template
            }
        }

        guard let template = bestMatch, bestScore > 0.3 else {
            return WorkflowIntent(
                objective: "generic_workflow",
                domain: "general",
                description: "Custom automation workflow",
                confidence: 0.25,
                triggerPattern: "manual",
                frequency: "on_demand",
                estimatedDuration: 30
            )
        }

        return WorkflowIntent(
            objective: template.objective,
            domain: template.domain,
            description: template.description,
            confidence: bestScore,
            triggerPattern: template.triggerPattern,
            frequency: template.frequency,
            estimatedDuration: estimateDuration(actions: actions)
        )
    }

    // MARK: - Template Registry (extensible)

    private static func buildWorkflowTemplates() -> [WorkflowTemplate] {
        [
            WorkflowTemplate(
                objective: "maintain_accounts_payable_tracker",
                domain: "accounts_payable",
                description: "Search Gmail for invoices, extract payment details, and log them to a Google Sheet",
                triggerPattern: "0 9 * * 1",
                frequency: "weekly",
                actionSequence: ["gmail_search", "gmail_open_email", "extract_data", "sheets_append"],
                requiredArtifacts: ["invoice_tracker", "invoice_email"],
                providerPreferences: ["gmail": "api", "sheets": "api"],
                keywordTriggers: ["invoice", "payment", "bill", "vendor", "amount", "due"],
                baseConfidence: 0.75
            ),
            WorkflowTemplate(
                objective: "lead_generation_from_linkedin",
                domain: "lead_generation",
                description: "Browse LinkedIn profiles, copy contact info, and build a lead list in Google Sheets",
                triggerPattern: "0 10 * * 1-5",
                frequency: "daily",
                actionSequence: ["open_url", "extract_data", "sheets_append"],
                requiredArtifacts: ["lead_list", "linkedin_profile"],
                providerPreferences: ["sheets": "api"],
                keywordTriggers: ["linkedin", "profile", "lead", "contact", "company", "title"],
                baseConfidence: 0.70
            ),
            WorkflowTemplate(
                objective: "generate_weekly_report",
                domain: "reporting",
                description: "Pull data from spreadsheets and Gmail, compile a weekly summary, send via email",
                triggerPattern: "0 9 * * 5",
                frequency: "weekly",
                actionSequence: ["sheets_read", "gmail_search", "extract_data", "gmail_send"],
                requiredArtifacts: ["report", "report_email"],
                providerPreferences: ["gmail": "api", "sheets": "api"],
                keywordTriggers: ["report", "weekly", "summary", "digest", "update", "status"],
                baseConfidence: 0.72
            ),
            WorkflowTemplate(
                objective: "expense_reconciliation",
                domain: "expense_management",
                description: "Find expense receipts in Gmail, extract amounts, log to expense tracker sheet",
                triggerPattern: "0 8 * * *",
                frequency: "daily",
                actionSequence: ["gmail_search", "gmail_open_email", "extract_data", "sheets_append"],
                requiredArtifacts: ["expense_tracker", "receipt_email"],
                providerPreferences: ["gmail": "api", "sheets": "api"],
                keywordTriggers: ["receipt", "expense", "spend", "purchase", "transaction"],
                baseConfidence: 0.73
            ),
            WorkflowTemplate(
                objective: "crm_contact_sync",
                domain: "crm",
                description: "Extract contact information from emails and maintain a contact list spreadsheet",
                triggerPattern: "0 14 * * *",
                frequency: "daily",
                actionSequence: ["gmail_search", "extract_data", "sheets_append"],
                requiredArtifacts: ["contact_list", "contact_data"],
                providerPreferences: ["gmail": "api", "sheets": "api"],
                keywordTriggers: ["contact", "email", "phone", "name", "company", "sync"],
                baseConfidence: 0.68
            ),
            WorkflowTemplate(
                objective: "file_download_and_organize",
                domain: "file_management",
                description: "Download attachments from Gmail and save them to organized folders",
                triggerPattern: "manual",
                frequency: "on_demand",
                actionSequence: ["gmail_search", "gmail_open_email", "click"],
                requiredArtifacts: ["email"],
                providerPreferences: ["gmail": "api"],
                keywordTriggers: ["attachment", "download", "file", "pdf", "document"],
                baseConfidence: 0.55
            ),
            WorkflowTemplate(
                objective: "form_fill_and_submit",
                domain: "data_entry",
                description: "Fill web forms with data from clipboard or spreadsheet",
                triggerPattern: "on_demand",
                frequency: "on_demand",
                actionSequence: ["open_url", "fill_form", "extract_data"],
                requiredArtifacts: ["web_page", "structured_data"],
                providerPreferences: [:],
                keywordTriggers: ["form", "submit", "register", "apply", "signup"],
                baseConfidence: 0.50
            )
        ]
    }

    // MARK: - Template Scoring

    private static func scoreTemplateMatch(
        template: WorkflowTemplate,
        actions: [SemanticAction],
        artifacts: [ExtractedArtifact]
    ) -> Double {
        var score = template.baseConfidence

        // Action sequence match: how many template actions appear in the actual actions?
        let actualActions = Set(actions.map { $0.action })
        let templateActions = Set(template.actionSequence)
        let actionOverlap = actualActions.intersection(templateActions)
        if !templateActions.isEmpty {
            let actionRatio = Double(actionOverlap.count) / Double(templateActions.count)
            score *= (0.5 + 0.5 * actionRatio)
        }

        // Artifact match: do we have the required artifact types?
        let actualArtifactTypes = Set(artifacts.map { $0.artifactType })
        let requiredTypes = Set(template.requiredArtifacts)
        let artifactOverlap = actualArtifactTypes.intersection(requiredTypes)
        if !requiredTypes.isEmpty {
            let artifactRatio = Double(artifactOverlap.count) / Double(requiredTypes.count)
            score *= (0.4 + 0.6 * artifactRatio)
        }

        // Keyword match: do artifacts/actions contain trigger keywords?
        let allText = (
            artifacts.flatMap { $0.fields.map { $0.value } } +
            artifacts.map { $0.title } +
            actions.map { $0.description }
        ).joined(separator: " ").lowercased()

        let keywordHits = template.keywordTriggers.filter { allText.contains($0.lowercased()) }
        if !template.keywordTriggers.isEmpty {
            let keywordRatio = Double(keywordHits.count) / Double(template.keywordTriggers.count)
            score *= (0.6 + 0.4 * keywordRatio)
        }

        // Penalty for having extra actions that don't fit
        let extraActions = actualActions.subtracting(templateActions)
        if extraActions.count > 2 {
            score *= 0.85
        }

        return min(score, 1.0)
    }

    // MARK: - Step 3: Workflow Plan Generation

    static func generatePlan(
        actions: [SemanticAction],
        artifacts: [ExtractedArtifact],
        intent: WorkflowIntent
    ) -> WorkflowPlan {
        let integrations = discoverRequiredIntegrations(actions: actions, artifacts: artifacts)
        let steps = buildPlanSteps(actions: actions)
        let strategy = buildExecutionStrategy(actions: actions, integrations: integrations)
        let readiness = assessReadiness(integrations: integrations, steps: steps)

        // Confidence breakdown
        let actionConf = actions.isEmpty ? 0 : actions.map(\.confidence).reduce(0, +) / Double(actions.count)
        let artifactConf = artifacts.isEmpty ? 0 : artifacts.map(\.confidence).reduce(0, +) / Double(artifacts.count)
        let coherenceConf = computeCoherenceConfidence(actions: actions, artifacts: artifacts)
        let objectiveConf = intent.confidence
        let overall = (actionConf * 0.25 + artifactConf * 0.25 + coherenceConf * 0.20 + objectiveConf * 0.30)

        return WorkflowPlan(
            objective: intent.objective,
            domain: intent.domain,
            confidence: WorkflowPlan.ConfidenceBreakdown(
                overallConfidence: overall,
                actionConfidence: actionConf,
                artifactConfidence: artifactConf,
                coherenceConfidence: coherenceConf,
                objectiveConfidence: objectiveConf
            ),
            artifacts: artifacts,
            intent: intent,
            requiredIntegrations: integrations,
            steps: steps,
            executionStrategy: strategy,
            automationReadiness: readiness
        )
    }

    private static func discoverRequiredIntegrations(
        actions: [SemanticAction], artifacts: [ExtractedArtifact]
    ) -> [WorkflowPlan.IntegrationRequirement] {
        var integrations: [String: WorkflowPlan.IntegrationRequirement] = [:]

        for action in actions {
            let provider = action.provider
            guard integrations[provider] == nil else { continue }

            switch provider {
            case "gmail":
                integrations[provider] = .init(
                    provider: "gmail",
                    reason: "Email actions detected (search/send)",
                    isConnected: GoogleOAuthManager.isConnected(),
                    requiredScopes: ["gmail.send", "gmail.readonly"]
                )
            case "sheets":
                integrations[provider] = .init(
                    provider: "sheets",
                    reason: "Spreadsheet actions detected (read/append)",
                    isConnected: GoogleOAuthManager.isConnected(),
                    requiredScopes: ["spreadsheets"]
                )
            case "browser", "chrome":
                integrations["browser"] = .init(
                    provider: "browser",
                    reason: "Web navigation required",
                    isConnected: true,
                    requiredScopes: []
                )
            default:
                integrations[provider] = .init(
                    provider: provider,
                    reason: "Desktop app automation",
                    isConnected: true,
                    requiredScopes: []
                )
            }
        }

        return Array(integrations.values)
    }

    private static func buildPlanSteps(actions: [SemanticAction]) -> [WorkflowPlan.PlanStep] {
        return actions.enumerated().map { (index, action) in
            WorkflowPlan.PlanStep(
                order: index + 1,
                semanticActionId: action.id,
                description: action.description,
                executionType: action.executionType,
                provider: action.provider,
                requiresReview: action.requiresReview
            )
        }
    }

    private static func buildExecutionStrategy(
        actions: [SemanticAction],
        integrations: [WorkflowPlan.IntegrationRequirement]
    ) -> WorkflowPlan.ExecutionStrategy {
        let cloudSteps = actions.filter { $0.executionType == "cloud" }
        let localSteps = actions.filter { $0.executionType == "local" }
        let allCloudFeasible = localSteps.isEmpty

        let cloudBlockers = localSteps.map { "\($0.action) requires desktop replay" }
        let fallbackMode = allCloudFeasible ? "retry_with_backoff" : "fallback_to_local"

        let primaryMode: String
        if cloudSteps.count > localSteps.count {
            primaryMode = "cloud_preferred"
        } else if localSteps.count > cloudSteps.count {
            primaryMode = "local_preferred"
        } else {
            primaryMode = "hybrid"
        }

        return WorkflowPlan.ExecutionStrategy(
            primaryMode: primaryMode,
            cloudFeasible: allCloudFeasible,
            cloudBlockers: cloudBlockers,
            fallbackMode: fallbackMode
        )
    }

    private static func assessReadiness(
        integrations: [WorkflowPlan.IntegrationRequirement],
        steps: [WorkflowPlan.PlanStep]
    ) -> WorkflowPlan.AutomationReadiness {
        var blockers: [String] = []
        var recommendations: [String] = []

        for integration in integrations where !integration.isConnected {
            blockers.append("\(integration.provider) is not connected. Go to Settings → Integrations to connect.")
            recommendations.append("Connect \(integration.provider) via OAuth for cloud execution.")
        }

        let reviewSteps = steps.filter { $0.requiresReview }
        if !reviewSteps.isEmpty {
            recommendations.append("\(reviewSteps.count) step(s) require manual review before first run.")
        }

        let localOnly = steps.filter { $0.executionType == "local" }
        if !localOnly.isEmpty {
            recommendations.append("\(localOnly.count) step(s) require Mirror running on your Mac. Consider recording these steps in an app with an API for full cloud execution.")
        }

        return WorkflowPlan.AutomationReadiness(
            isReady: blockers.isEmpty,
            blockers: blockers,
            recommendations: recommendations
        )
    }

    private static func computeCoherenceConfidence(
        actions: [SemanticAction], artifacts: [ExtractedArtifact]
    ) -> Double {
        guard !actions.isEmpty, !artifacts.isEmpty else { return 0.3 }

        // Coherence = do actions and artifacts share the same domain?
        let actionProviders = Set(actions.map { $0.provider })
        let artifactSources = Set(artifacts.map { $0.sourceApp })

        // High coherence: artifacts come from the same sources actions target
        let overlap = actionProviders.intersection(artifactSources)
        let totalSources = actionProviders.union(artifactSources)

        guard !totalSources.isEmpty else { return 0.3 }
        return Double(overlap.count) / Double(totalSources.count)
    }

    // MARK: - Helpers

    private static func estimateDuration(actions: [SemanticAction]) -> Double {
        // Rough estimate: 2-5 seconds per action
        return Double(actions.count) * 3.0
    }

    // MARK: - Step 4: Full Pipeline

    static func extract(
        from actions: [SemanticAction],
        events: [EventTapManager.CapturedEvent],
        sessionDir: URL? = nil
    ) -> WorkflowPlan {
        let artifacts = extractArtifacts(from: actions, events: events, sessionDir: sessionDir)
        let intent = inferIntent(actions: actions, artifacts: artifacts)
        return generatePlan(actions: actions, artifacts: artifacts, intent: intent)
    }

    // MARK: - JSON Output

    static func toJSON(_ plan: WorkflowPlan) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(plan),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    // MARK: - Context Summary for AI Prompt

    static func buildIntentSummary(from plan: WorkflowPlan) -> String {
        var lines: [String] = []
        lines.append("## Workflow Intent Analysis (pre-extracted)")
        lines.append("**Objective:** \(plan.objective) (\(plan.domain))")
        lines.append("**Confidence:** \(Int(plan.confidence.overallConfidence * 100))%")
        lines.append("")

        if !plan.artifacts.isEmpty {
            lines.append("### Detected Artifacts")
            for artifact in plan.artifacts {
                let fieldList = artifact.fields.map { "\($0.name): \($0.value)" }.joined(separator: ", ")
                lines.append("- **\(artifact.artifactType)** [\(artifact.domain)] — \(artifact.title)")
                if !fieldList.isEmpty { lines.append("  Fields: \(fieldList)") }
            }
            lines.append("")
        }

        lines.append("### Required Integrations")
        for integration in plan.requiredIntegrations {
            let status = integration.isConnected ? "connected" : "NOT connected"
            lines.append("- **\(integration.provider):** \(integration.reason) (\(status))")
        }
        lines.append("")

        lines.append("### Execution Strategy")
        lines.append("- Primary mode: \(plan.executionStrategy.primaryMode)")
        lines.append("- Cloud feasible: \(plan.executionStrategy.cloudFeasible ? "yes" : "no")")
        if !plan.executionStrategy.cloudBlockers.isEmpty {
            for blocker in plan.executionStrategy.cloudBlockers {
                lines.append("  - Blocker: \(blocker)")
            }
        }
        lines.append("")

        if !plan.automationReadiness.recommendations.isEmpty {
            lines.append("### Recommendations")
            for rec in plan.automationReadiness.recommendations {
                lines.append("- \(rec)")
            }
            lines.append("")
        }

        lines.append("---")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Session Context (internal data structure for extraction)

private struct SessionContext {
    let visitedURLs: [String]
    let allTypedText: [String]
    let allClipboardContent: [String]
    let windowTitles: [String]
    let appNames: [String]

    func combinedText(limit: Int) -> String {
        let combined = (allTypedText + allClipboardContent + windowTitles).joined(separator: " ")
        return String(combined.prefix(limit))
    }
}

private func buildSessionContext(events: [EventTapManager.CapturedEvent]) -> SessionContext {
    var urls: [String] = []
    var typedText: [String] = []
    var clipboardContent: [String] = []
    var titles: [String] = []
    var apps: [String] = []
    var seenURLs = Set<String>()
    var currentTyped = ""

    for event in events {
        // Collect unique URLs
        if let url = event.targetURL, !url.isEmpty, !seenURLs.contains(url) {
            seenURLs.insert(url)
            urls.append(url)
        }

        // Track app names
        if let app = event.targetApp, !app.isEmpty, apps.last != app {
            apps.append(app)
            if let url = event.targetURL, !url.isEmpty {
                titles.append("\(app) — \(url)")
            }
        }

        // Build typed text buffers
        if event.type == "keyDown", let chars = event.characters, event.redacted != true {
            if chars == "\r" || chars == "\n" {
                if !currentTyped.isEmpty {
                    typedText.append(currentTyped)
                    currentTyped = ""
                }
            } else {
                currentTyped += chars
            }
        }

        // Clipboard changes
        if event.type == "clipboardChange", let clip = event.clipboardSnapshot, !clip.isEmpty {
            clipboardContent.append(clip)
        }
    }

    // Flush any remaining typed text
    if !currentTyped.isEmpty {
        typedText.append(currentTyped)
    }

    return SessionContext(
        visitedURLs: urls,
        allTypedText: typedText,
        allClipboardContent: clipboardContent,
        windowTitles: titles,
        appNames: apps
    )
}
