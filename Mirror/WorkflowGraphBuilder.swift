import Foundation

// MARK: - Canonical Workflow Graph Models

struct WorkflowGraph: Codable {
    let id: String
    var title: String
    var description: String
    let objective: String?
    let domain: String?

    var confidence: GraphConfidence
    var nodes: [WorkflowNode]
    var edges: [WorkflowEdge]

    // Execution metadata
    var requiredIntegrations: [GraphIntegration]
    var executionStrategy: GraphExecutionStrategy
    var automationReadiness: GraphReadiness

    // Entity context
    var detectedEntities: [GraphEntity]
    var dataFlowPaths: [DataFlowPath]

    struct GraphConfidence: Codable {
        var nodeConfidence: Double      // avg of all node confidences
        var edgeConfidence: Double      // avg of all edge confidences
        var coherenceScore: Double      // graph structure quality
        var overallConfidence: Double   // weighted composite
    }

    struct GraphIntegration: Codable {
        let provider: String
        let reason: String
        let isConnected: Bool
        let requiredScopes: [String]
        let usedByNodeIds: [String]     // which nodes need this integration
    }

    struct GraphExecutionStrategy: Codable {
        let primaryMode: String          // "cloud" | "local" | "hybrid"
        let cloudNodeCount: Int
        let localNodeCount: Int
        let desktopNodeCount: Int
        let apiReplacementsAvailable: [String: String] // desktopNodeId → apiNodeType
        let cloudFeasible: Bool
        let cloudBlockers: [String]
    }

    struct GraphReadiness: Codable {
        let isReady: Bool
        let blockers: [String]
        let recommendations: [String]
    }

    struct GraphEntity: Codable {
        let id: String
        let name: String                 // "Invoice", "Customer", "PDF", etc.
        let type: String                 // "business_object" | "file" | "document" | "person"
        let sourceNodeId: String?        // which node produced this entity?
        let consumerNodeIds: [String]    // which nodes consume this entity?
        let fields: [String: String]     // detected structured properties
    }

    struct DataFlowPath: Codable {
        let id: String
        let description: String          // e.g. "Invoice number flows from Gmail to Spreadsheet"
        let sourceNodeId: String
        let sourceEntity: String?        // e.g. "invoice_number"
        let targetNodeId: String
        let targetField: String?         // e.g. "amount"
        let transformation: String?      // "extract", "map", "copy", "enrich"
    }
}

// MARK: - Workflow Node

struct WorkflowNode: Codable, Identifiable {
    let id: String
    let type: NodeType
    let category: NodeCategory
    var label: String                    // human-readable, entity-aware
    var confidence: Double
    var provider: String?                // "gmail", "sheets", "chrome", etc.
    var executionType: ExecutionType     // cloud | local | desktop
    var apiEquivalent: String?           // if desktop, what API node type would replace it?

    var position: NodePosition?          // for UI layout
    var metadata: NodeMetadata           // action-specific data
    var inputPorts: [Port]
    var outputPorts: [Port]

    struct NodePosition: Codable {
        var x: Double
        var y: Double
    }

    struct Port: Codable {
        let id: String
        let name: String
        let direction: PortDirection    // input | output
        let dataType: String?           // "string", "file", "json", "table"
        let entityType: String?         // "Invoice", "PDF", "Email", etc.
        var connected: Bool
    }

    enum ExecutionType: String, Codable {
        case cloud
        case local
        case desktop
    }

    enum PortDirection: String, Codable {
        case input
        case output
    }

    enum NodeCategory: String, Codable {
        case trigger
        case dataSource
        case transformation
        case decision
        case action
        case desktop
    }
}

// MARK: - Canonical Node Types

struct NodeType: Codable, RawRepresentable, Hashable {
    let rawValue: String

    init(rawValue: String) { self.rawValue = rawValue }

    // Triggers
    static let scheduleTrigger = NodeType(rawValue: "schedule_trigger")
    static let emailTrigger = NodeType(rawValue: "email_trigger")
    static let fileTrigger = NodeType(rawValue: "file_trigger")
    static let webhookTrigger = NodeType(rawValue: "webhook_trigger")
    static let manualTrigger = NodeType(rawValue: "manual_trigger")

    // Data Sources
    static let gmailSearch = NodeType(rawValue: "gmail_search")
    static let gmailFetch = NodeType(rawValue: "gmail_fetch")
    static let spreadsheetRead = NodeType(rawValue: "spreadsheet_read")
    static let documentRead = NodeType(rawValue: "document_read")
    static let websiteFetch = NodeType(rawValue: "website_fetch")
    static let fileRead = NodeType(rawValue: "file_read")
    static let clipboardRead = NodeType(rawValue: "clipboard_read")

    // Transformations
    static let extractFields = NodeType(rawValue: "extract_fields")
    static let classify = NodeType(rawValue: "classify")
    static let summarize = NodeType(rawValue: "summarize")
    static let mapFields = NodeType(rawValue: "map_fields")
    static let filter = NodeType(rawValue: "filter")
    static let validate = NodeType(rawValue: "validate")
    static let aggregate = NodeType(rawValue: "aggregate")
    static let transformText = NodeType(rawValue: "transform_text")

    // Decisions
    static let condition = NodeType(rawValue: "condition")
    static let branch = NodeType(rawValue: "branch")
    static let approvalRequired = NodeType(rawValue: "approval_required")

    // Actions
    static let sendEmail = NodeType(rawValue: "send_email")
    static let appendSheetRow = NodeType(rawValue: "append_sheet_row")
    static let createRecord = NodeType(rawValue: "create_record")
    static let uploadFile = NodeType(rawValue: "upload_file")
    static let notifyUser = NodeType(rawValue: "notify_user")
    static let downloadAttachment = NodeType(rawValue: "download_attachment")

    // Desktop (fallback)
    static let openApplication = NodeType(rawValue: "open_application")
    static let clickUIElement = NodeType(rawValue: "click_ui_element")
    static let typeText = NodeType(rawValue: "type_text")
    static let desktopNavigation = NodeType(rawValue: "desktop_navigation")
}

// MARK: - Node Metadata

struct NodeMetadata: Codable {
    var url: String?
    var query: String?
    var pattern: String?
    var to: String?
    var subject: String?
    var body: String?
    var spreadsheetId: String?
    var range: String?
    var values: [String]?
    var filePath: String?
    var appName: String?
    var typedText: String?
    var screenshotPath: String?
    var condition: String?
    var transform: String?
    var inputFrom: String?
    var outputAs: String?
    var entityContext: String?       // e.g. "invoice", "lead", "report"
    var entityFields: [String: String]? // structured entity properties
}

// MARK: - Workflow Edge

struct WorkflowEdge: Codable, Identifiable {
    let id: String
    let sourceNodeId: String
    let sourcePortId: String?
    let targetNodeId: String
    let targetPortId: String?
    let edgeType: EdgeType
    var confidence: Double
    var label: String?               // e.g. "Invoice PDF", "Extracted rows"
    var metadata: EdgeMetadata

    enum EdgeType: String, Codable {
        case controlFlow      // "next step"
        case dataFlow         // "data moves from A to B"
        case entityFlow       // "entity X produced by A consumed by B"
        case dependency        // "B depends on A's output"
        case trigger           // "trigger activates this node"
    }

    struct EdgeMetadata: Codable {
        var sourceEntity: String?    // e.g. "invoice_number"
        var targetField: String?     // e.g. "amount"
        var transformation: String?  // "extract", "map", "copy", "enrich", "filter"
        var dataType: String?        // "string", "file", "json", "table"
    }
}

// MARK: - Semantic → Node Type Mapping

fileprivate let actionToNodeType: [String: NodeType] = [
    "gmail_search":     .gmailSearch,
    "gmail_send":       .sendEmail,
    "gmail_open_email": .gmailFetch,
    "sheets_append":    .appendSheetRow,
    "sheets_read":      .spreadsheetRead,
    "open_url":         .websiteFetch,
    "extract_data":     .extractFields,
    "web_request":      .websiteFetch,
    "send_email":       .sendEmail,
    "file_read":        .fileRead,
    "file_write":       .uploadFile,
    "type_text":        .typeText,
    "fill_form":        .typeText,
    "click":            .clickUIElement,
    "open_application": .openApplication,
    "run_script":       .transformText,
    "condition":        .condition,
    "transform":        .transformText,
    "paste_text":       .typeText,
    "press_shortcut":   .typeText,
    "screenshot":       .fileRead,
    "wait":             .mapFields,   // placeholder
    "copy_clipboard":   .clipboardRead,
]

fileprivate let nodeCategoryMap: [NodeType: WorkflowNode.NodeCategory] = [
    .scheduleTrigger: .trigger,
    .emailTrigger: .trigger,
    .fileTrigger: .trigger,
    .webhookTrigger: .trigger,
    .manualTrigger: .trigger,
    .gmailSearch: .dataSource,
    .gmailFetch: .dataSource,
    .spreadsheetRead: .dataSource,
    .websiteFetch: .dataSource,
    .fileRead: .dataSource,
    .clipboardRead: .dataSource,
    .documentRead: .dataSource,
    .extractFields: .transformation,
    .classify: .transformation,
    .summarize: .transformation,
    .mapFields: .transformation,
    .filter: .transformation,
    .validate: .transformation,
    .aggregate: .transformation,
    .transformText: .transformation,
    .condition: .decision,
    .branch: .decision,
    .approvalRequired: .decision,
    .sendEmail: .action,
    .appendSheetRow: .action,
    .createRecord: .action,
    .uploadFile: .action,
    .notifyUser: .action,
    .downloadAttachment: .action,
    .openApplication: .desktop,
    .clickUIElement: .desktop,
    .typeText: .desktop,
    .desktopNavigation: .desktop,
]

// API equivalents for desktop nodes
fileprivate let apiReplacements: [NodeType: NodeType] = [
    .openApplication: .websiteFetch,
    .clickUIElement: .extractFields,
    .typeText: .extractFields,
    .desktopNavigation: .websiteFetch,
]

// MARK: - Entity Context

fileprivate let entityNamesByDomain: [String: String] = [
    "accounts_payable": "Invoice",
    "lead_generation": "Lead",
    "crm": "Contact",
    "expense_management": "Expense",
    "reporting": "Report",
    "finance": "Transaction",
    "marketing": "Campaign",
]

fileprivate let entityLabels: [String: String] = [
    "invoice_tracker": "Invoice Tracker",
    "invoice_email": "Invoice Email",
    "lead_list": "Lead List",
    "contact_list": "Contact List",
    "financial_data": "Financial Data",
    "expense_tracker": "Expense Tracker",
    "receipt_email": "Receipt Email",
    "report": "Report",
    "linkedin_profile": "LinkedIn Profile",
    "email": "Email",
    "spreadsheet": "Spreadsheet",
    "web_page": "Web Page",
]

// MARK: - Workflow Graph Builder

struct WorkflowGraphBuilder {

    // MARK: - Main Entry Point

    static func build(
        from actions: [SemanticAction],
        artifacts: [ExtractedArtifact] = [],
        intent: WorkflowIntent? = nil,
        sessionMetadata: [String: Any] = [:]
    ) -> WorkflowGraph {
        let graphId = UUID().uuidString
        let nodes = buildNodes(from: actions, artifacts: artifacts, intent: intent)
        let edges = buildEdges(from: nodes, actions: actions, artifacts: artifacts)
        let entities = extractEntities(from: artifacts, nodes: nodes)
        let dataFlows = inferDataFlows(actions: actions, nodes: nodes, edges: edges, entities: entities)
        let confidence = computeGraphConfidence(nodes: nodes, edges: edges, dataFlows: dataFlows)
        let integrations = buildIntegrations(from: nodes)
        let strategy = buildExecutionStrategy(from: nodes)
        let readiness = buildReadiness(integrations: integrations, nodes: nodes)

        return WorkflowGraph(
            id: graphId,
            title: intent?.description ?? "Automated Workflow",
            description: buildGraphDescription(nodes: nodes, intent: intent),
            objective: intent?.objective,
            domain: intent?.domain,
            confidence: confidence,
            nodes: nodes,
            edges: edges,
            requiredIntegrations: integrations,
            executionStrategy: strategy,
            automationReadiness: readiness,
            detectedEntities: entities,
            dataFlowPaths: dataFlows
        )
    }

    // MARK: - Node Construction

    private static func buildNodes(
        from actions: [SemanticAction],
        artifacts: [ExtractedArtifact],
        intent: WorkflowIntent?
    ) -> [WorkflowNode] {
        var nodes: [WorkflowNode] = []
        var portCounter = 0

        // 1. Trigger node (always first)
        let triggerType: NodeType = intent?.triggerPattern == "manual" ? .manualTrigger : .scheduleTrigger
        nodes.append(WorkflowNode(
            id: "trigger",
            type: triggerType,
            category: .trigger,
            label: triggerType == .manualTrigger ? "Manual Trigger" : "Schedule: \(intent?.triggerPattern ?? "daily")",
            confidence: 0.95,
            provider: nil,
            executionType: .cloud,
            apiEquivalent: nil,
            position: nil,
            metadata: NodeMetadata(),
            inputPorts: [],
            outputPorts: [.init(id: "trigger-out-0", name: "start", direction: .output, dataType: nil, entityType: nil, connected: false)]
        ))

        // 2. Action nodes
        for action in actions {
            let nodeType = actionToNodeType[action.action] ?? .typeText
            let category = nodeCategoryMap[nodeType] ?? .desktop
            let execType: WorkflowNode.ExecutionType = action.executionType == "cloud" ? .cloud : .desktop
            let apiEquiv = execType == .desktop ? apiReplacements[nodeType]?.rawValue : nil

            // Entity-aware label
            let label = buildEntityAwareLabel(action: action, nodeType: nodeType, artifacts: artifacts, intent: intent)

            // Build ports
            let inputPorts: [WorkflowNode.Port] = action.inputSources.isEmpty
                ? []
                : action.inputSources.enumerated().map { i, src in
                    portCounter += 1
                    return WorkflowNode.Port(id: "\(action.id)-in-\(i)", name: src, direction: .input, dataType: nil, entityType: nil, connected: false)
                }
            let outputPorts: [WorkflowNode.Port] = action.outputKey.map { key in
                portCounter += 1
                return [WorkflowNode.Port(id: "\(action.id)-out-0", name: key, direction: .output, dataType: nil, entityType: action.payload.spreadsheetId != nil ? "Spreadsheet" : nil, connected: false)]
            } ?? []

            nodes.append(WorkflowNode(
                id: action.id,
                type: nodeType,
                category: category,
                label: label,
                confidence: action.confidence,
                provider: action.provider,
                executionType: execType,
                apiEquivalent: apiEquiv,
                position: nil,
                metadata: buildNodeMetadata(from: action),
                inputPorts: inputPorts,
                outputPorts: outputPorts
            ))
        }

        return nodes
    }

    private static func buildEntityAwareLabel(
        action: SemanticAction,
        nodeType: NodeType,
        artifacts: [ExtractedArtifact],
        intent: WorkflowIntent?
    ) -> String {
        let domain = intent?.domain ?? ""
        let entityName = entityNamesByDomain[domain]

        switch nodeType {
        case .gmailSearch:
            if let query = action.payload.query, !query.isEmpty {
                return entityName.map { "Search Gmail for \($0): \(query)" } ?? "Search Gmail: \(query)"
            }
            return "Search Gmail"
        case .gmailFetch:
            return entityName.map { "Open \($0) Email" } ?? "Open Email"
        case .sendEmail:
            return entityName.map { "Send \($0) Email" } ?? "Send Email"
        case .appendSheetRow:
            return entityName.map { "Append \($0) to Sheet" } ?? "Append Row to Sheet"
        case .spreadsheetRead:
            return entityName.map { "Read \($0) Data" } ?? "Read Spreadsheet"
        case .extractFields:
            if let entity = entityName { return "Extract \(entity) Fields" }
            return action.description
        case .websiteFetch:
            if let url = action.payload.url, let host = URL(string: url)?.host {
                return "Navigate to \(host)"
            }
            return "Open URL"
        case .typeText:
            if let text = action.payload.typedText, text.count < 60 {
                return "Type '\(text)'"
            }
            return "Type Text"
        case .clickUIElement:
            return "Click Element"
        case .clipboardRead:
            return "Copy to Clipboard"
        case .openApplication:
            return action.payload.appName.map { "Open \($0)" } ?? "Open App"
        default:
            return action.description
        }
    }

    private static func buildNodeMetadata(from action: SemanticAction) -> NodeMetadata {
        NodeMetadata(
            url: action.payload.url,
            query: action.payload.query,
            pattern: action.payload.extractedValue,
            to: action.payload.to,
            subject: action.payload.subject,
            body: action.payload.body,
            spreadsheetId: action.payload.spreadsheetId,
            range: action.payload.range,
            values: action.payload.values,
            filePath: action.payload.filePath,
            appName: action.payload.appName,
            typedText: action.payload.typedText,
            inputFrom: action.inputSources.first,
            outputAs: action.outputKey
        )
    }

    // MARK: - Edge Construction

    private static func buildEdges(
        from nodes: [WorkflowNode],
        actions: [SemanticAction],
        artifacts: [ExtractedArtifact]
    ) -> [WorkflowEdge] {
        var edges: [WorkflowEdge] = []
        var edgeId = 0

        guard !nodes.isEmpty else { return edges }

        let actionNodes = nodes.filter { $0.id != "trigger" }

        // 1. Trigger → first action node
        if let firstAction = actionNodes.first {
            edgeId += 1
            edges.append(WorkflowEdge(
                id: "edge\(edgeId)",
                sourceNodeId: "trigger",
                sourcePortId: "trigger-out-0",
                targetNodeId: firstAction.id,
                targetPortId: firstAction.inputPorts.first?.id,
                edgeType: .trigger,
                confidence: 0.95,
                label: nil,
                metadata: .init()
            ))
        }

        // 2. Control flow: sequential action chaining
        for i in 0..<(actionNodes.count - 1) {
            let source = actionNodes[i]
            let target = actionNodes[i + 1]

            // Skip if already connected via data flow
            let alreadyConnected = edges.contains { $0.targetNodeId == target.id }
            guard !alreadyConnected else { continue }

            edgeId += 1
            edges.append(WorkflowEdge(
                id: "edge\(edgeId)",
                sourceNodeId: source.id,
                sourcePortId: source.outputPorts.first?.id,
                targetNodeId: target.id,
                targetPortId: target.inputPorts.first?.id,
                edgeType: .controlFlow,
                confidence: 0.80,
                label: nil,
                metadata: .init()
            ))
        }

        // 3. Data flow edges: action.inputSources → upstream output
        for targetAction in actions {
            for inputSource in targetAction.inputSources {
                // Find the node that produces this output
                guard let sourceAction = actions.first(where: { $0.outputKey == inputSource }) else { continue }
                guard let sourceNode = nodes.first(where: { $0.id == sourceAction.id }),
                      let targetNode = nodes.first(where: { $0.id == targetAction.id }) else { continue }

                // Don't create duplicate data flow edges
                let exists = edges.contains { edge in
                    edge.sourceNodeId == sourceNode.id &&
                    edge.targetNodeId == targetNode.id &&
                    edge.edgeType == .dataFlow
                }
                guard !exists else { continue }

                edgeId += 1
                edges.append(WorkflowEdge(
                    id: "edge\(edgeId)",
                    sourceNodeId: sourceNode.id,
                    sourcePortId: sourceNode.outputPorts.first?.id,
                    targetNodeId: targetNode.id,
                    targetPortId: targetNode.inputPorts.first?.id,
                    edgeType: .dataFlow,
                    confidence: 0.85,
                    label: sourceAction.outputKey,
                    metadata: WorkflowEdge.EdgeMetadata(
                        sourceEntity: sourceAction.outputKey,
                        targetField: nil,
                        transformation: "copy",
                        dataType: "any"
                    )
                ))
            }
        }

        // 4. Entity flow edges: artifact → action node
        for artifact in artifacts {
            for rel in artifact.relationships where rel.relationship == "derived_from" {
                guard let sourceArtifact = artifacts.first(where: { $0.id == rel.targetArtifactId }) else { continue }

                // Find nodes that produced/consumed these artifacts
                let sourceProvider = sourceArtifact.sourceApp
                let targetProvider = artifact.sourceApp

                if let sourceNode = actionNodes.first(where: { $0.provider == sourceProvider }),
                   let targetNode = actionNodes.first(where: { $0.provider == targetProvider }),
                   sourceNode.id != targetNode.id {
                    edgeId += 1
                    edges.append(WorkflowEdge(
                        id: "edge\(edgeId)",
                        sourceNodeId: sourceNode.id,
                        sourcePortId: nil,
                        targetNodeId: targetNode.id,
                        targetPortId: nil,
                        edgeType: .entityFlow,
                        confidence: 0.70,
                        label: artifact.title,
                        metadata: WorkflowEdge.EdgeMetadata(
                            sourceEntity: sourceArtifact.artifactType,
                            targetField: artifact.title,
                            transformation: "extract",
                            dataType: "entity"
                        )
                    ))
                }
            }
        }

        return edges
    }

    // MARK: - Entity Extraction

    private static func extractEntities(
        from artifacts: [ExtractedArtifact],
        nodes: [WorkflowNode]
    ) -> [WorkflowGraph.GraphEntity] {
        var entities: [WorkflowGraph.GraphEntity] = []
        var entityId = 0

        for artifact in artifacts {
            entityId += 1
            let entityName = entityLabels[artifact.artifactType] ?? artifact.artifactType

            // Find which node produced this artifact (by provider match)
            let sourceNodeId = nodes.first(where: { $0.provider == artifact.sourceApp })?.id

            // Find which nodes consume this artifact (by domain match)
            let consumerNodeIds = artifact.relationships
                .filter { $0.relationship == "derived_from" }
                .compactMap { rel -> String? in
                    let targetArtifact = artifacts.first(where: { $0.id == rel.targetArtifactId })
                    return nodes.first(where: { $0.provider == targetArtifact?.sourceApp })?.id
                }

            let fields = Dictionary(uniqueKeysWithValues: artifact.fields.map { ($0.name, $0.value) })

            entities.append(WorkflowGraph.GraphEntity(
                id: "entity\(entityId)",
                name: entityName,
                type: artifact.domain.contains("invoice") || artifact.domain.contains("expense") ? "business_object"
                    : artifact.artifactType.contains("email") ? "document"
                    : artifact.artifactType.contains("sheet") || artifact.artifactType.contains("spreadsheet") ? "document"
                    : "file",
                sourceNodeId: sourceNodeId,
                consumerNodeIds: consumerNodeIds,
                fields: fields
            ))
        }

        return entities
    }

    // MARK: - Data Flow Inference

    private static func inferDataFlows(
        actions: [SemanticAction],
        nodes: [WorkflowNode],
        edges: [WorkflowEdge],
        entities: [WorkflowGraph.GraphEntity]
    ) -> [WorkflowGraph.DataFlowPath] {
        var paths: [WorkflowGraph.DataFlowPath] = []
        var pathId = 0

        // For each data flow edge, describe the entity movement
        for edge in edges where edge.edgeType == .dataFlow || edge.edgeType == .entityFlow {
            let sourceNode = nodes.first(where: { $0.id == edge.sourceNodeId })
            let targetNode = nodes.first(where: { $0.id == edge.targetNodeId })

            let sourceEntity = entities.first(where: { $0.sourceNodeId == edge.sourceNodeId || $0.consumerNodeIds.contains(edge.sourceNodeId) })
            let targetEntity = entities.first(where: { $0.consumerNodeIds.contains(edge.targetNodeId) || $0.sourceNodeId == edge.targetNodeId })

            pathId += 1
            let description: String
            if let srcEnt = sourceEntity?.name, let tgtEnt = targetEntity?.name {
                description = "\(srcEnt) data flows from \(sourceNode?.label ?? "source") to \(targetNode?.label ?? "target") as \(tgtEnt)"
            } else if let srcEnt = sourceEntity?.name {
                description = "\(srcEnt) extracted from \(sourceNode?.label ?? "source") and sent to \(targetNode?.label ?? "target")"
            } else if let label = edge.label {
                description = "'\(label)' flows from \(sourceNode?.label ?? "source") to \(targetNode?.label ?? "target")"
            } else {
                description = "Data flows from \(sourceNode?.label ?? "source") to \(targetNode?.label ?? "target")"
            }

            paths.append(WorkflowGraph.DataFlowPath(
                id: "flow\(pathId)",
                description: description,
                sourceNodeId: edge.sourceNodeId,
                sourceEntity: edge.metadata.sourceEntity,
                targetNodeId: edge.targetNodeId,
                targetField: edge.metadata.targetField,
                transformation: edge.metadata.transformation
            ))
        }

        return paths
    }

    // MARK: - Graph Confidence

    private static func computeGraphConfidence(
        nodes: [WorkflowNode],
        edges: [WorkflowEdge],
        dataFlows: [WorkflowGraph.DataFlowPath]
    ) -> WorkflowGraph.GraphConfidence {
        let actionNodes = nodes.filter { $0.id != "trigger" }
        let nodeConf = actionNodes.isEmpty ? 0 : actionNodes.map(\.confidence).reduce(0, +) / Double(actionNodes.count)
        let edgeConf = edges.isEmpty ? 0 : edges.map(\.confidence).reduce(0, +) / Double(edges.count)

        // Coherence: good if every action node has at least one connection
        let connectedNodes = Set(edges.flatMap { [$0.sourceNodeId, $0.targetNodeId] })
        let unconnectedCount = actionNodes.filter { !connectedNodes.contains($0.id) }.count
        let connectivityRatio = actionNodes.isEmpty ? 0 : Double(actionNodes.count - unconnectedCount) / Double(actionNodes.count)

        // Coherence: good if there are data flows
        let dataFlowBonus = min(Double(dataFlows.count) * 0.05, 0.15)

        let coherenceScore = min(connectivityRatio * 0.7 + dataFlowBonus + 0.15, 1.0)
        let overall = nodeConf * 0.30 + edgeConf * 0.25 + coherenceScore * 0.45

        return WorkflowGraph.GraphConfidence(
            nodeConfidence: nodeConf,
            edgeConfidence: edgeConf,
            coherenceScore: coherenceScore,
            overallConfidence: overall
        )
    }

    // MARK: - Integrations

    private static func buildIntegrations(from nodes: [WorkflowNode]) -> [WorkflowGraph.GraphIntegration] {
        var integrations: [String: WorkflowGraph.GraphIntegration] = [:]

        for node in nodes {
            guard let provider = node.provider else { continue }
            guard integrations[provider] == nil else {
                // Append node ID to existing integration
                var existing = integrations[provider]!
                existing = WorkflowGraph.GraphIntegration(
                    provider: existing.provider,
                    reason: existing.reason,
                    isConnected: existing.isConnected,
                    requiredScopes: existing.requiredScopes,
                    usedByNodeIds: existing.usedByNodeIds + [node.id]
                )
                integrations[provider] = existing
                continue
            }

            switch provider {
            case "gmail":
                integrations[provider] = .init(
                    provider: "gmail",
                    reason: "Email operations required",
                    isConnected: GoogleOAuthManager.isConnected(),
                    requiredScopes: ["gmail.send", "gmail.readonly"],
                    usedByNodeIds: [node.id]
                )
            case "sheets":
                integrations[provider] = .init(
                    provider: "sheets",
                    reason: "Spreadsheet operations required",
                    isConnected: GoogleOAuthManager.isConnected(),
                    requiredScopes: ["spreadsheets"],
                    usedByNodeIds: [node.id]
                )
            default:
                integrations[provider] = .init(
                    provider: provider,
                    reason: "\(provider) integration required",
                    isConnected: true,
                    requiredScopes: [],
                    usedByNodeIds: [node.id]
                )
            }
        }

        return Array(integrations.values)
    }

    // MARK: - Execution Strategy

    private static func buildExecutionStrategy(from nodes: [WorkflowNode]) -> WorkflowGraph.GraphExecutionStrategy {
        let actionNodes = nodes.filter { $0.id != "trigger" }
        let cloudNodes = actionNodes.filter { $0.executionType == .cloud }
        let desktopNodes = actionNodes.filter { $0.executionType == .desktop }
        let localNodes = actionNodes.filter { $0.executionType == .local }

        let apiReplacements: [String: String] = desktopNodes.reduce(into: [:]) { dict, node in
            if let api = node.apiEquivalent { dict[node.id] = api }
        }

        let cloudBlockers = desktopNodes.map { "\($0.label) requires desktop replay (no API equivalent available)" }

        let primaryMode: String
        if cloudNodes.count > desktopNodes.count {
            primaryMode = "cloud_preferred"
        } else if desktopNodes.count > cloudNodes.count {
            primaryMode = "local_preferred"
        } else {
            primaryMode = "hybrid"
        }

        return WorkflowGraph.GraphExecutionStrategy(
            primaryMode: primaryMode,
            cloudNodeCount: cloudNodes.count,
            localNodeCount: localNodes.count,
            desktopNodeCount: desktopNodes.count,
            apiReplacementsAvailable: apiReplacements,
            cloudFeasible: desktopNodes.isEmpty,
            cloudBlockers: cloudBlockers
        )
    }

    private static func buildReadiness(
        integrations: [WorkflowGraph.GraphIntegration],
        nodes: [WorkflowNode]
    ) -> WorkflowGraph.GraphReadiness {
        var blockers: [String] = []
        var recommendations: [String] = []

        for integration in integrations where !integration.isConnected {
            blockers.append("\(integration.provider) is not connected")
            recommendations.append("Connect \(integration.provider) in Settings → Integrations")
        }

        let desktopNodes = nodes.filter { $0.executionType == .desktop }
        if !desktopNodes.isEmpty {
            recommendations.append("\(desktopNodes.count) step(s) use desktop replay — Mirror must be running on your Mac")
        }

        let reviewNodes = nodes.filter { $0.confidence < 0.5 }
        if !reviewNodes.isEmpty {
            recommendations.append("\(reviewNodes.count) low-confidence node(s) — review before deploying")
        }

        return WorkflowGraph.GraphReadiness(
            isReady: blockers.isEmpty,
            blockers: blockers,
            recommendations: recommendations
        )
    }

    // MARK: - Graph Description

    private static func buildGraphDescription(nodes: [WorkflowNode], intent: WorkflowIntent?) -> String {
        let actionNodes = nodes.filter { $0.id != "trigger" }
        let nodeList = actionNodes.map { $0.label }.joined(separator: " → ")
        let prefix = intent.map { "\($0.description): " } ?? ""
        return "\(prefix)\(nodeList)"
    }

    // MARK: - JSON Serialization

    static func toJSON(_ graph: WorkflowGraph) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(graph),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    // MARK: - Context Summary for AI Prompt

    static func buildGraphSummary(from graph: WorkflowGraph) -> String {
        var lines: [String] = []
        lines.append("## Workflow Graph")
        lines.append("**\(graph.title)**")
        if let obj = graph.objective { lines.append("Objective: \(obj) (\(graph.domain ?? "general"))") }
        lines.append("Confidence: \(Int(graph.confidence.overallConfidence * 100))%")
        lines.append("")

        if !graph.detectedEntities.isEmpty {
            lines.append("### Entities")
            for entity in graph.detectedEntities {
                let fields = entity.fields.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
                lines.append("- \(entity.name) (\(entity.type))" + (fields.isEmpty ? "" : " — \(fields)"))
            }
            lines.append("")
        }

        lines.append("### Nodes")
        for node in graph.nodes {
            let badge = node.executionType == .cloud ? "☁" : node.executionType == .desktop ? "💻" : "🔧"
            let cat = node.category.rawValue
            let conf = Int(node.confidence * 100)
            lines.append("- **\(node.id):** \(badge) \(node.type.rawValue) [\(cat)] — \(node.label) (\(conf)%)")
        }
        lines.append("")

        if !graph.edges.isEmpty {
            lines.append("### Edges")
            for edge in graph.edges {
                lines.append("- \(edge.sourceNodeId) → \(edge.targetNodeId) [\(edge.edgeType.rawValue)]\(edge.label.map { " '\($0)'" } ?? "") (\(Int(edge.confidence * 100))%)")
            }
            lines.append("")
        }

        if !graph.dataFlowPaths.isEmpty {
            lines.append("### Data Flows")
            for flow in graph.dataFlowPaths {
                lines.append("- \(flow.description)")
            }
            lines.append("")
        }

        lines.append("Execution: \(graph.executionStrategy.primaryMode) (\(graph.executionStrategy.cloudNodeCount) cloud, \(graph.executionStrategy.desktopNodeCount) desktop)")
        lines.append("Ready to deploy: \(graph.automationReadiness.isReady ? "yes" : "no")")
        if !graph.automationReadiness.blockers.isEmpty {
            for blocker in graph.automationReadiness.blockers {
                lines.append("  ⚠ \(blocker)")
            }
        }

        lines.append("\n---")
        return lines.joined(separator: "\n")
    }

    // MARK: - Convenience: Full Pipeline

    static func buildFullGraph(
        from semanticActions: [SemanticAction],
        artifacts: [ExtractedArtifact] = [],
        intent: WorkflowIntent? = nil,
        events: [EventTapManager.CapturedEvent] = [],
        metadata: [String: Any] = [:]
    ) -> WorkflowGraph {
        let resolvedIntent = intent ?? WorkflowIntentExtractor.inferIntent(
            actions: semanticActions,
            artifacts: artifacts
        )
        let resolvedArtifacts = artifacts.isEmpty
            ? WorkflowIntentExtractor.extractArtifacts(from: semanticActions, events: events)
            : artifacts

        return build(
            from: semanticActions,
            artifacts: resolvedArtifacts,
            intent: resolvedIntent,
            sessionMetadata: metadata
        )
    }
}
