import Foundation

// MARK: - ═══════════════════════════════════════════
// MARK: Editor-Ready Workflow Graph
// MARK: ═══════════════════════════════════════════

/// The canonical workflow graph upgraded for visual editing.
/// Backward compatible with analysis-only WorkflowGraph via `migrate(from:)`.
struct EditorGraph: Codable {
    var id: String
    var version: Int
    var title: String
    var description: String
    var objective: String?
    var domain: String?

    var nodes: [EditorNode]
    var edges: [EditorEdge]
    var entities: [EditorEntity]?
    var dataFlows: [EditorDataFlow]?

    var confidence: EditorGraphConfidence
    var executionStrategy: EditorExecutionStrategy
    var readiness: EditorReadiness
    var requiredIntegrations: [EditorIntegration]

    var versions: [GraphVersion]
    var aiEditHistory: [AIEditCommand]
    var createdAt: Date
    var updatedAt: Date
    var generatedBy: GenerationSource

    enum GenerationSource: String, Codable {
        case ai
        case recording
        case manual
        case hybrid
    }
}

// MARK: - ═══════════════════════════════════════════
// MARK: Editor Node
// MARK: ═══════════════════════════════════════════

struct EditorNode: Codable, Identifiable {
    let id: String
    var type: String                     // canonical NodeType rawValue
    var category: EditorNodeCategory
    var label: String                    // display name
    var description: String              // tooltip / detail text

    // Visual Rendering
    var position: NodePosition
    var size: NodeSize
    var color: NodeColor
    var icon: String                     // SF Symbol name or emoji
    var badge: NodeBadge?

    // Configuration
    var config: NodeConfiguration
    var inputs: [NodePort]
    var outputs: [NodePort]

    // Metadata
    var metadata: EditorNodeMetadata
    var confidence: Double
    var executionType: ExecutionType

    // Edit State
    var isEditable: Bool
    var isUserModified: Bool
    var generatedByAI: Bool
    var apiReplacementAvailable: String? // node type that could replace this

    // Lifecycle
    var createdAt: Date
    var updatedAt: Date

    // MARK: Sub-types

    struct NodePosition: Codable {
        var x: Double
        var y: Double
    }

    struct NodeSize: Codable {
        var width: Double       // default 240
        var height: Double      // default 120
    }

    struct NodeColor: Codable {
        var background: String  // hex
        var border: String      // hex
        var accent: String      // hex for the category stripe
    }

    struct NodeBadge: Codable {
        var text: String
        var color: String       // hex background
        var icon: String?       // emoji
    }

    enum EditorNodeCategory: String, Codable {
        case trigger
        case dataSource
        case transformation
        case decision
        case action
        case desktop
    }

    enum ExecutionType: String, Codable {
        case cloud
        case local
        case desktop
    }
}

// MARK: - ═══════════════════════════════════════════
// MARK: Node Configuration System
// MARK: ═══════════════════════════════════════════

struct NodeConfiguration: Codable {
    var parameters: [ConfigParameter]
    var validationRules: [ValidationRule]
    var defaultValues: [String: String]

    struct ConfigParameter: Codable, Identifiable {
        let id: String
        let key: String                // e.g. "query", "spreadsheetId"
        var label: String              // e.g. "Search Query"
        var type: ConfigParameterType
        var value: String?
        var valueSource: ValueSource   // where did the value come from?
        var isRequired: Bool
        var placeholder: String?
        var hint: String?
        var options: [ConfigOption]?   // for select/enum types
        var isSensitive: Bool = false          // password/API key fields
    }

    struct ConfigOption: Codable {
        let label: String
        let value: String
    }

    enum ConfigParameterType: String, Codable {
        case string
        case number
        case boolean
        case select           // dropdown
        case multiSelect       // multi-choice
        case keyBinding        // keyboard shortcut
        case variable          // {{variable}} reference
        case filePath
        case url
        case secret            // masked input
        case json              // structured editor
        case cron              // schedule expression
    }

    enum ValueSource: String, Codable {
        case aiGenerated
        case userProvided
        case fromRecording
        case fromVariable
        case defaultValue
    }

    struct ValidationRule: Codable, Identifiable {
        let id: String
        let parameterKey: String
        let rule: ValidationRuleType
        let message: String
    }

    enum ValidationRuleType: String, Codable {
        case required
        case minLength
        case maxLength
        case pattern          // regex
        case enumValue
        case validURL
        case validCron
        case validEmail
        case numericRange
    }
}

// MARK: - ═══════════════════════════════════════════
// MARK: Node Metadata
// MARK: ═══════════════════════════════════════════

struct EditorNodeMetadata: Codable {
    var confidence: Double
    var rationale: String              // why the AI created this node
    var evidence: [EvidenceItem]       // what signals support this node
    var aiPromptContext: String?       // the prompt fragment that generated this
    var requiresReview: Bool
    var reviewReason: String?

    struct EvidenceItem: Codable {
        let type: EvidenceType
        let description: String
        let confidence: Double
    }

    enum EvidenceType: String, Codable {
        case urlDetected
        case appNameMatch
        case typedTextPattern
        case clipboardContent
        case actionSequence
        case fieldMapping
        case userConfirmed
        case aiInferred
    }
}

// MARK: - ═══════════════════════════════════════════
// MARK: Port System
// MARK: ═══════════════════════════════════════════

struct NodePort: Codable, Identifiable {
    let id: String
    var name: String
    var label: String
    var direction: PortDirection
    var dataType: PortDataType
    var entityType: String?            // "Invoice", "PDF", etc.
    var isConnected: Bool
    var isRequired: Bool
    var acceptsMultiple: Bool          // can multiple edges connect here?

    enum PortDirection: String, Codable {
        case input
        case output
    }

    enum PortDataType: String, Codable {
        case trigger
        case string
        case number
        case boolean
        case json
        case file
        case table
        case email
        case any
    }
}

// MARK: - ═══════════════════════════════════════════
// MARK: Editor Edge
// MARK: ═══════════════════════════════════════════

struct EditorEdge: Codable, Identifiable {
    let id: String
    var sourceNodeId: String
    var sourcePortId: String?
    var targetNodeId: String
    var targetPortId: String?
    var edgeType: EditorEdgeType
    var label: String?
    var confidence: Double
    var metadata: EdgeMetadata
    var isUserCreated: Bool
    var createdAt: Date

    enum EditorEdgeType: String, Codable {
        case controlFlow
        case dataFlow
        case entityFlow
        case dependency
        case trigger
        case errorFlow        // what happens on failure
    }

    struct EdgeMetadata: Codable {
        var sourceEntity: String?
        var targetField: String?
        var transformation: String?
        var dataType: String?
    }
}

// MARK: - ═══════════════════════════════════════════
// MARK: Execution State Models
// MARK: ═══════════════════════════════════════════

struct WorkflowRun: Codable, Identifiable {
    let id: String
    let workflowId: String
    let version: Int
    var status: ExecutionStatus
    var startedAt: Date
    var endedAt: Date?
    var duration: TimeInterval?
    var nodeRuns: [NodeRun]
    var summary: String
    var errorSummary: String?
    var triggerSource: String?         // "schedule", "manual", "webhook"
    var logs: [RunLogEntry]?

    struct RunLogEntry: Codable {
        let timestamp: Date
        let level: LogLevel
        let message: String
        let nodeId: String?
    }

    enum LogLevel: String, Codable {
        case debug, info, warning, error
    }
}

struct NodeRun: Codable, Identifiable {
    let id: String
    let nodeId: String
    var status: ExecutionStatus
    var startedAt: Date
    var endedAt: Date?
    var duration: TimeInterval?
    var inputSnapshot: [String: String]?   // what went in
    var outputSnapshot: [String: String]?  // what came out
    var errorMessage: String?
    var retryCount: Int
    var stepNumber: Int                 // order in execution sequence
}

enum ExecutionStatus: String, Codable {
    case pending
    case running
    case success
    case warning          // completed but with issues
    case failed
    case skipped          // conditionally skipped
    case cancelled
    case retrying
}

// MARK: - ═══════════════════════════════════════════
// MARK: Node Inspection Models
// MARK: ═══════════════════════════════════════════

struct NodeInspection: Codable {
    let nodeId: String
    var views: InspectionViews

    struct InspectionViews: Codable {
        var summary: SummaryView
        var configuration: ConfigurationView
        var execution: ExecutionView?
        var evidence: EvidenceView
        var dataFlow: DataFlowView
    }

    struct SummaryView: Codable {
        let label: String
        let description: String
        let category: String
        let executionType: String
        let confidence: Double
        let rationale: String
        var tags: [String]              // e.g. "ai-generated", "review-needed"
    }

    struct ConfigurationView: Codable {
        var parameters: [NodeConfiguration.ConfigParameter]
        var validationErrors: [String]?
    }

    struct ExecutionView: Codable {
        var lastRun: NodeRun?
        var runHistory: [NodeRun]?
        var averageDuration: TimeInterval?
        var successRate: Double?
    }

    struct EvidenceView: Codable {
        var items: [EvidenceItemSummary]
        var totalConfidence: Double
        var aiGenerated: Bool
    }

    struct EvidenceItemSummary: Codable {
        let type: String
        let description: String
        let confidence: Double
    }

    struct DataFlowView: Codable {
        var inputs: [DataFlowEntry]
        var outputs: [DataFlowEntry]
    }

    struct DataFlowEntry: Codable {
        let portName: String
        let connectedNodeId: String?
        let connectedNodeLabel: String?
        let dataType: String
        let entityType: String?
    }
}

// MARK: - ═══════════════════════════════════════════
// MARK: Graph Editing Operations
// MARK: ═══════════════════════════════════════════

struct GraphEditor {

    // MARK: Node Operations

    static func insertNode(_ node: EditorNode, into graph: EditorGraph, after afterNodeId: String? = nil) -> EditorGraph {
        var g = graph
        g.nodes.append(node)
        g.version += 1
        g.updatedAt = Date()

        if let afterId = afterNodeId, g.nodes.contains(where: { $0.id == afterId }) {
            let edgeId = "edge_\(UUID().uuidString.prefix(8))"
            let edge = EditorEdge(
                id: edgeId, sourceNodeId: afterId, sourcePortId: nil,
                targetNodeId: node.id, targetPortId: nil,
                edgeType: .controlFlow, label: nil, confidence: 0.9,
                metadata: .init(), isUserCreated: true, createdAt: Date()
            )
            g.edges.append(edge)
        }

        return g
    }

    static func deleteNode(_ nodeId: String, from graph: EditorGraph) -> EditorGraph {
        var g = graph
        g.nodes.removeAll { $0.id == nodeId }
        g.edges.removeAll { $0.sourceNodeId == nodeId || $0.targetNodeId == nodeId }
        g.version += 1
        g.updatedAt = Date()
        return g
    }

    static func replaceNode(_ nodeId: String, with newNode: EditorNode, in graph: EditorGraph) -> EditorGraph {
        var g = graph
        guard let idx = g.nodes.firstIndex(where: { $0.id == nodeId }) else { return g }

        // Reconnect edges
        g.edges = g.edges.map { edge in
            var e = edge
            if e.sourceNodeId == nodeId { e.sourceNodeId = newNode.id }
            if e.targetNodeId == nodeId { e.targetNodeId = newNode.id }
            return e
        }
        g.nodes[idx] = newNode
        g.nodes[idx].isUserModified = true
        g.nodes[idx].updatedAt = Date()
        g.version += 1
        g.updatedAt = Date()
        return g
    }

    /// Replace a desktop node with its API equivalent
    static func upgradeToAPI(nodeId: String, apiNodeType: String, in graph: EditorGraph) -> EditorGraph {
        guard let node = graph.nodes.first(where: { $0.id == nodeId }),
              node.category == .desktop else { return graph }

        var newNode = node
        newNode.type = apiNodeType
        newNode.category = categoryForNodeType(apiNodeType)
        newNode.executionType = .cloud
        newNode.color = categoryColor(newNode.category)
        newNode.icon = iconForNodeType(apiNodeType)
        newNode.label = "\(apiNodeType) (upgraded from \(node.type))"
        newNode.isUserModified = true
        newNode.generatedByAI = false
        newNode.apiReplacementAvailable = nil
        newNode.updatedAt = Date()

        return replaceNode(nodeId, with: newNode, in: graph)
    }

    // MARK: Edge Operations

    static func connect(
        from sourceNodeId: String, sourcePort: String?,
        to targetNodeId: String, targetPort: String?,
        edgeType: EditorEdge.EditorEdgeType = .controlFlow,
        in graph: EditorGraph
    ) -> EditorGraph {
        var g = graph

        // Update port connection state
        if let srcPort = sourcePort {
            if let srcIdx = g.nodes.firstIndex(where: { $0.id == sourceNodeId }),
               let portIdx = g.nodes[srcIdx].outputs.firstIndex(where: { $0.id == srcPort }) {
                g.nodes[srcIdx].outputs[portIdx].isConnected = true
            }
        }
        if let tgtPort = targetPort {
            if let tgtIdx = g.nodes.firstIndex(where: { $0.id == targetNodeId }),
               let portIdx = g.nodes[tgtIdx].inputs.firstIndex(where: { $0.id == tgtPort }) {
                g.nodes[tgtIdx].inputs[portIdx].isConnected = true
            }
        }

        let edgeId = "edge_\(UUID().uuidString.prefix(8))"
        g.edges.append(EditorEdge(
            id: edgeId, sourceNodeId: sourceNodeId, sourcePortId: sourcePort,
            targetNodeId: targetNodeId, targetPortId: targetPort,
            edgeType: edgeType, label: nil, confidence: 0.9,
            metadata: .init(), isUserCreated: true, createdAt: Date()
        ))

        g.version += 1
        g.updatedAt = Date()
        return g
    }

    static func disconnect(edgeId: String, in graph: EditorGraph) -> EditorGraph {
        var g = graph
        guard let edge = g.edges.first(where: { $0.id == edgeId }) else { return g }

        // Update port states
        if let srcPort = edge.sourcePortId,
           let srcIdx = g.nodes.firstIndex(where: { $0.id == edge.sourceNodeId }),
           let portIdx = g.nodes[srcIdx].outputs.firstIndex(where: { $0.id == srcPort }) {
            g.nodes[srcIdx].outputs[portIdx].isConnected = false
        }
        if let tgtPort = edge.targetPortId,
           let tgtIdx = g.nodes.firstIndex(where: { $0.id == edge.targetNodeId }),
           let portIdx = g.nodes[tgtIdx].inputs.firstIndex(where: { $0.id == tgtPort }) {
            g.nodes[tgtIdx].inputs[portIdx].isConnected = false
        }

        g.edges.removeAll { $0.id == edgeId }
        g.version += 1
        g.updatedAt = Date()
        return g
    }

    // MARK: Helpers

    private static func categoryForNodeType(_ type: String) -> EditorNode.EditorNodeCategory {
        switch type {
        case let t where t.contains("trigger"): return .trigger
        case let t where t.contains("search") || t.contains("fetch") || t.contains("read"): return .dataSource
        case let t where t.contains("extract") || t.contains("transform") || t.contains("filter") || t.contains("classify"): return .transformation
        case let t where t.contains("condition") || t.contains("branch") || t.contains("approval"): return .decision
        case let t where t.contains("send") || t.contains("append") || t.contains("upload") || t.contains("notify"): return .action
        default: return .desktop
        }
    }

    private static func categoryColor(_ category: EditorNode.EditorNodeCategory) -> EditorNode.NodeColor {
        switch category {
        case .trigger: return .init(background: "#1a1a2e", border: "#eab308", accent: "#eab308")
        case .dataSource: return .init(background: "#1a1a2e", border: "#3b82f6", accent: "#3b82f6")
        case .transformation: return .init(background: "#1a1a2e", border: "#8b5cf6", accent: "#8b5cf6")
        case .decision: return .init(background: "#1a1a2e", border: "#f59e0b", accent: "#f59e0b")
        case .action: return .init(background: "#1a1a2e", border: "#22c55e", accent: "#22c55e")
        case .desktop: return .init(background: "#1a1a2e", border: "#6b7280", accent: "#6b7280")
        }
    }

    private static func iconForNodeType(_ type: String) -> String {
        switch type {
        case "schedule_trigger": return "clock"
        case "manual_trigger": return "hand.tap"
        case "gmail_search": return "magnifyingglass"
        case "gmail_fetch": return "envelope.open"
        case "send_email": return "paperplane"
        case "spreadsheet_read": return "tablecells"
        case "append_sheet_row": return "plus.rectangle"
        case "extract_fields": return "scissors"
        case "condition": return "arrow.triangle.branch"
        case "website_fetch": return "globe"
        case "type_text": return "keyboard"
        case "click_ui_element": return "cursorarrow.click"
        case "open_application": return "app.badge"
        default: return "square"
        }
    }
}

// MARK: - ═══════════════════════════════════════════
// MARK: Versioning System
// MARK: ═══════════════════════════════════════════

struct GraphVersion: Codable, Identifiable {
    let id: String
    let versionNumber: Int
    let createdAt: Date
    let createdBy: VersionCreator
    let description: String          // e.g. "AI generated from recording" or "User added Gmail node"
    let snapshot: GraphSnapshot      // full graph state at this version
    let diff: GraphDiff?             // changes from previous version

    enum VersionCreator: String, Codable {
        case ai
        case user
        case system      // auto-upgrade, migration
    }

    struct GraphSnapshot: Codable {
        let nodeCount: Int
        let edgeCount: Int
        let confidence: Double
        let nodeIds: [String]
        let edgeIds: [String]
    }

    struct GraphDiff: Codable {
        let addedNodes: [String]
        let removedNodes: [String]
        let modifiedNodes: [String]
        let addedEdges: [String]
        let removedEdges: [String]
        let replacedNodes: [ReplacedNode]

        struct ReplacedNode: Codable {
            let old: String
            let new: String
        }
    }
}

struct VersionManager {
    static func createVersion(from graph: EditorGraph, description: String, createdBy: GraphVersion.VersionCreator) -> GraphVersion {
        return GraphVersion(
            id: "v\(graph.version)",
            versionNumber: graph.version,
            createdAt: Date(),
            createdBy: createdBy,
            description: description,
            snapshot: GraphVersion.GraphSnapshot(
                nodeCount: graph.nodes.count,
                edgeCount: graph.edges.count,
                confidence: graph.confidence.overallConfidence,
                nodeIds: graph.nodes.map(\.id),
                edgeIds: graph.edges.map(\.id)
            ),
            diff: nil
        )
    }

    static func snapshot(_ graph: EditorGraph) {
        var g = graph
        let version = createVersion(from: g, description: "Snapshot", createdBy: .system)
        g.versions.append(version)
    }

    static func rollback(to versionNumber: Int, in graph: EditorGraph) -> EditorGraph? {
        guard graph.versions.contains(where: { $0.versionNumber == versionNumber }) else {
            return nil
        }
        // In a real implementation, the snapshot would contain full graph state.
        // For the model layer, we return the graph with version metadata pointing to the rollback.
        var g = graph
        g.version = versionNumber
        g.updatedAt = Date()
        return g
    }
}

// MARK: - ═══════════════════════════════════════════
// MARK: Automatic Layout System
// MARK: ═══════════════════════════════════════════

struct GraphLayoutEngine {

    /// Compute deterministic positions for all nodes using a layered topological sort.
    /// Nodes are arranged left-to-right in columns by their depth in the DAG.
    static func layout(_ graph: inout EditorGraph) {
        guard !graph.nodes.isEmpty else { return }

        // Build adjacency: node ID → list of successor IDs
        var successors: [String: [String]] = [:]
        var predecessors: [String: [String]] = [:]

        for node in graph.nodes {
            successors[node.id] = []
            predecessors[node.id] = []
        }
        for edge in graph.edges {
            successors[edge.sourceNodeId, default: []].append(edge.targetNodeId)
            predecessors[edge.targetNodeId, default: []].append(edge.sourceNodeId)
        }

        // Kahn's algorithm: compute topological layers
        var inDegree: [String: Int] = [:]
        for node in graph.nodes {
            inDegree[node.id] = predecessors[node.id]?.count ?? 0
        }

        var layers: [[String]] = []
        var queue = graph.nodes.filter { (inDegree[$0.id] ?? 0) == 0 }.map(\.id)

        while !queue.isEmpty {
            layers.append(queue)
            var nextQueue: [String] = []
            for nodeId in queue {
                for succ in successors[nodeId] ?? [] {
                    inDegree[succ, default: 1] -= 1
                    if inDegree[succ] == 0 {
                        nextQueue.append(succ)
                    }
                }
            }
            queue = nextQueue
        }

        // Handle disconnected nodes: add as final layer
        let placed = Set(layers.flatMap { $0 })
        let disconnected = graph.nodes.map(\.id).filter { !placed.contains($0) }
        if !disconnected.isEmpty {
            layers.append(disconnected)
        }

        // Assign positions
        let columnSpacing: Double = 320
        let rowSpacing: Double = 160
        let startX: Double = 80
        let startY: Double = 80

        for (colIdx, layer) in layers.enumerated() {
            let columnX = startX + Double(colIdx) * columnSpacing
            let totalHeight = Double(layer.count - 1) * rowSpacing
            let startOffsetY = startY - totalHeight / 2

            for (rowIdx, nodeId) in layer.enumerated() {
                guard let nodeIdx = graph.nodes.firstIndex(where: { $0.id == nodeId }) else { continue }
                graph.nodes[nodeIdx].position = .init(
                    x: columnX,
                    y: startOffsetY + Double(rowIdx) * rowSpacing
                )
                graph.nodes[nodeIdx].size = .init(width: 240, height: 120)
            }
        }
    }

    /// Layout nodes in a vertical waterfall (useful for narrow displays or mobile)
    static func layoutVertical(_ graph: inout EditorGraph) {
        let topo = topologicalOrder(graph)
        for (index, nodeId) in topo.enumerated() {
            guard let nodeIdx = graph.nodes.firstIndex(where: { $0.id == nodeId }) else { continue }
            graph.nodes[nodeIdx].position = .init(x: 200, y: 80 + Double(index) * 160)
            graph.nodes[nodeIdx].size = .init(width: 320, height: 96)
        }
    }

    private static func topologicalOrder(_ graph: EditorGraph) -> [String] {
        var visited = Set<String>()
        var order: [String] = []

        func dfs(_ nodeId: String) {
            guard !visited.contains(nodeId) else { return }
            visited.insert(nodeId)
            let outgoing = graph.edges.filter { $0.sourceNodeId == nodeId }.map(\.targetNodeId)
            for target in outgoing { dfs(target) }
            order.insert(nodeId, at: 0)
        }

        // Start from trigger nodes, then remaining
        let triggers = graph.nodes.filter { $0.category == .trigger }.map(\.id)
        for tid in triggers { dfs(tid) }
        for node in graph.nodes where !visited.contains(node.id) { dfs(node.id) }

        return order
    }
}

// MARK: - ═══════════════════════════════════════════
// MARK: AI Editing Support
// MARK: ═══════════════════════════════════════════

struct AIEditCommand: Codable, Identifiable {
    let id: String
    let timestamp: Date
    let naturalLanguage: String        // e.g. "Use column G instead."
    let resolvedIntent: AIEditIntent   // parsed intent
    let status: AIEditStatus
    let resultSummary: String?

    struct AIEditIntent: Codable {
        let action: AIEditAction
        let targetNodeIds: [String]
        let newValues: [String: String]?  // parameter updates
        let targetEdgeIds: [String]?
    }

    enum AIEditAction: String, Codable {
        case changeParameter      // "Use column G instead"
        case replaceNode          // "Replace Gmail with Outlook"
        case addNode              // "Add a Slack notification"
        case removeNode           // "Remove the approval step"
        case reconnect            // "Send to Sheets instead of Email"
        case addCondition         // "Only process invoices from Acme"
        case addDataFlow          // "Also copy the vendor name"
        case adjustSchedule       // "Run every Monday at 8am instead"
        case changeMapping        // "Map vendor_name to column B"
        case explainStep          // "Why is this step here?"
        case optimize             // "Make this fully cloud-based"
    }

    enum AIEditStatus: String, Codable {
        case proposed             // AI suggested, awaiting confirmation
        case accepted             // user approved
        case rejected             // user declined
        case applied              // applied to the graph
        case failed               // application failed
    }
}

struct AIEditor {
    /// Parse a natural language command into an edit intent
    static func parse(command: String, graph: EditorGraph) -> AIEditCommand.AIEditIntent {
        let lower = command.lowercased()

        // Pattern matching for common commands
        if lower.contains("replace") || lower.contains("instead of") {
            return AIEditCommand.AIEditIntent(
                action: .replaceNode,
                targetNodeIds: inferTargetNodes(from: command, in: graph),
                newValues: nil,
                targetEdgeIds: nil
            )
        }
        if lower.contains("add") || lower.contains("insert") {
            return AIEditCommand.AIEditIntent(
                action: .addNode,
                targetNodeIds: [],
                newValues: nil,
                targetEdgeIds: nil
            )
        }
        if lower.contains("remove") || lower.contains("delete") {
            return AIEditCommand.AIEditIntent(
                action: .removeNode,
                targetNodeIds: inferTargetNodes(from: command, in: graph),
                newValues: nil,
                targetEdgeIds: nil
            )
        }
        if lower.contains("column") || lower.contains("field") || lower.contains("instead") {
            return AIEditCommand.AIEditIntent(
                action: .changeParameter,
                targetNodeIds: inferTargetNodes(from: command, in: graph),
                newValues: extractParameterUpdates(from: command),
                targetEdgeIds: nil
            )
        }
        if lower.contains("only") || lower.contains("filter") || lower.contains("condition") {
            return AIEditCommand.AIEditIntent(
                action: .addCondition,
                targetNodeIds: inferTargetNodes(from: command, in: graph),
                newValues: ["condition": command],
                targetEdgeIds: nil
            )
        }
        if lower.contains("schedule") || lower.contains("run") || lower.contains("every") {
            return AIEditCommand.AIEditIntent(
                action: .adjustSchedule,
                targetNodeIds: graph.nodes.filter { $0.category == .trigger }.map(\.id),
                newValues: extractParameterUpdates(from: command),
                targetEdgeIds: nil
            )
        }

        return AIEditCommand.AIEditIntent(
            action: .explainStep,
            targetNodeIds: inferTargetNodes(from: command, in: graph),
            newValues: nil,
            targetEdgeIds: nil
        )
    }

    private static func inferTargetNodes(from command: String, in graph: EditorGraph) -> [String] {
        let lower = command.lowercased()
        return graph.nodes.filter { node in
            lower.contains(node.type.lowercased()) ||
            lower.contains(node.label.lowercased()) ||
            lower.contains(node.category.rawValue.lowercased())
        }.map(\.id)
    }

    private static func extractParameterUpdates(from command: String) -> [String: String] {
        // Extract key=value or "X to Y" patterns
        var updates: [String: String] = [:]
        if let range = command.range(of: " to ") {
            updates["target"] = String(command[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        return updates
    }
}

// MARK: - ═══════════════════════════════════════════
// MARK: Supporting Models (confidence, strategy, etc.)
// MARK: ═══════════════════════════════════════════

struct EditorGraphConfidence: Codable {
    var nodeConfidence: Double
    var edgeConfidence: Double
    var coherenceScore: Double
    var overallConfidence: Double
}

struct EditorExecutionStrategy: Codable {
    var primaryMode: String
    var cloudNodeCount: Int
    var desktopNodeCount: Int
    var apiReplacementsAvailable: [String: String]
    var cloudFeasible: Bool
    var cloudBlockers: [String]
}

struct EditorReadiness: Codable {
    var isReady: Bool
    var blockers: [String]
    var recommendations: [String]
}

struct EditorIntegration: Codable {
    var provider: String
    var reason: String
    var isConnected: Bool
    var requiredScopes: [String]
    var usedByNodeIds: [String]
}

struct EditorEntity: Codable {
    var id: String
    var name: String
    var type: String
    var sourceNodeId: String?
    var consumerNodeIds: [String]
    var fields: [String: String]
}

struct EditorDataFlow: Codable {
    var id: String
    var description: String
    var sourceNodeId: String
    var sourceEntity: String?
    var targetNodeId: String
    var targetField: String?
    var transformation: String?
}

// MARK: - ═══════════════════════════════════════════
// MARK: Node Configuration Registry
// MARK: ═══════════════════════════════════════════

/// Predefined configurations for every node type.
/// The visual editor uses this to render parameter forms.
struct NodeConfigRegistry {
    static func configuration(for nodeType: String) -> NodeConfiguration {
        switch nodeType {
        case "schedule_trigger":
            return NodeConfiguration(
                parameters: [
                    .init(id: "cron", key: "cron", label: "Schedule (Cron)", type: .cron,
                          value: "0 9 * * *", valueSource: .aiGenerated, isRequired: true,
                          placeholder: "0 9 * * *", hint: "Standard 5-field cron expression"),
                    .init(id: "timezone", key: "timezone", label: "Timezone", type: .select,
                          value: "America/New_York", valueSource: .defaultValue, isRequired: false,
                          placeholder: nil, hint: nil,
                          options: [
                            .init(label: "Eastern", value: "America/New_York"),
                            .init(label: "Central", value: "America/Chicago"),
                            .init(label: "Mountain", value: "America/Denver"),
                            .init(label: "Pacific", value: "America/Los_Angeles"),
                          ])
                ],
                validationRules: [
                    .init(id: "val1", parameterKey: "cron", rule: .validCron, message: "Must be a valid cron expression")
                ],
                defaultValues: ["cron": "0 9 * * 1-5"]
            )

        case "gmail_search":
            return NodeConfiguration(
                parameters: [
                    .init(id: "query", key: "query", label: "Search Query", type: .string,
                          value: nil, valueSource: .aiGenerated, isRequired: true,
                          placeholder: "from:vendor subject:invoice", hint: "Gmail search syntax"),
                    .init(id: "maxResults", key: "maxResults", label: "Max Results", type: .number,
                          value: "10", valueSource: .defaultValue, isRequired: false,
                          placeholder: "10", hint: "Maximum emails to return")
                ],
                validationRules: [
                    .init(id: "val1", parameterKey: "query", rule: .required, message: "Search query is required")
                ],
                defaultValues: ["maxResults": "10"]
            )

        case "send_email":
            return NodeConfiguration(
                parameters: [
                    .init(id: "to", key: "to", label: "To", type: .string,
                          value: nil, valueSource: .fromVariable, isRequired: true,
                          placeholder: "{{recipient}}", hint: "Email address or variable"),
                    .init(id: "subject", key: "subject", label: "Subject", type: .string,
                          value: nil, valueSource: .aiGenerated, isRequired: true,
                          placeholder: "Weekly Report", hint: nil),
                    .init(id: "body", key: "body", label: "Body", type: .string,
                          value: nil, valueSource: .fromVariable, isRequired: false,
                          placeholder: "Report body text", hint: "Supports {{variables}}")
                ],
                validationRules: [
                    .init(id: "val1", parameterKey: "to", rule: .validEmail, message: "Must be a valid email address"),
                    .init(id: "val2", parameterKey: "subject", rule: .required, message: "Subject is required")
                ],
                defaultValues: [:]
            )

        case "append_sheet_row":
            return NodeConfiguration(
                parameters: [
                    .init(id: "spreadsheetId", key: "spreadsheetId", label: "Spreadsheet ID", type: .string,
                          value: nil, valueSource: .fromRecording, isRequired: true,
                          placeholder: "1BxiMVs0...", hint: "From the sheet URL: /d/SPREADSHEET_ID/"),
                    .init(id: "range", key: "range", label: "Range", type: .string,
                          value: "Sheet1!A:Z", valueSource: .defaultValue, isRequired: true,
                          placeholder: "Sheet1!A:Z", hint: "Sheet name and column range")
                ],
                validationRules: [
                    .init(id: "val1", parameterKey: "spreadsheetId", rule: .required, message: "Spreadsheet ID is required")
                ],
                defaultValues: ["range": "Sheet1!A:Z"]
            )

        case "extract_fields":
            return NodeConfiguration(
                parameters: [
                    .init(id: "pattern", key: "pattern", label: "Extraction Pattern", type: .string,
                          value: nil, valueSource: .aiGenerated, isRequired: false,
                          placeholder: "regex or field name", hint: "Regular expression to extract values"),
                    .init(id: "outputAs", key: "outputAs", label: "Output Variable", type: .variable,
                          value: nil, valueSource: .aiGenerated, isRequired: false,
                          placeholder: "invoice_number", hint: "Variable name for downstream steps")
                ],
                validationRules: [],
                defaultValues: [:]
            )

        case "condition":
            return NodeConfiguration(
                parameters: [
                    .init(id: "condition", key: "condition", label: "Condition", type: .string,
                          value: nil, valueSource: .aiGenerated, isRequired: true,
                          placeholder: "{{amount}} > 0", hint: "Expression using variables"),
                    .init(id: "trueBranch", key: "trueBranch", label: "True Branch", type: .string,
                          value: "continue", valueSource: .defaultValue, isRequired: false,
                          placeholder: nil, hint: nil),
                    .init(id: "falseBranch", key: "falseBranch", label: "False Branch", type: .string,
                          value: "skip", valueSource: .defaultValue, isRequired: false,
                          placeholder: nil, hint: nil)
                ],
                validationRules: [
                    .init(id: "val1", parameterKey: "condition", rule: .required, message: "Condition is required")
                ],
                defaultValues: ["trueBranch": "continue", "falseBranch": "skip"]
            )

        default:
            // Generic fallback
            return NodeConfiguration(
                parameters: [],
                validationRules: [],
                defaultValues: [:]
            )
        }
    }
}

// MARK: - ═══════════════════════════════════════════
// MARK: Migration: WorkflowGraph → EditorGraph
// MARK: ═══════════════════════════════════════════

struct EditorGraphMigrator {
    static func migrate(from graph: WorkflowGraph) -> EditorGraph {
        let editorNodes = graph.nodes.map { node in
            let cat = mapCategory(node.category)
            return EditorNode(
                id: node.id, type: node.type.rawValue, category: cat,
                label: node.label, description: node.label,
                position: .init(x: 0, y: 0),  // will be re-laid out
                size: .init(width: 240, height: 120),
                color: categoryColor(cat),
                icon: iconForType(node.type.rawValue),
                badge: node.confidence < 0.5 ? .init(text: "Low conf.", color: "#ef4444") : nil,
                config: NodeConfigRegistry.configuration(for: node.type.rawValue),
                inputs: node.inputPorts.map { port in
                    NodePort(id: port.id, name: port.name, label: port.name,
                             direction: .input, dataType: .any, entityType: port.entityType,
                             isConnected: port.connected, isRequired: false, acceptsMultiple: false)
                },
                outputs: node.outputPorts.map { port in
                    NodePort(id: port.id, name: port.name, label: port.name,
                             direction: .output, dataType: .any, entityType: port.entityType,
                             isConnected: port.connected, isRequired: false, acceptsMultiple: false)
                },
                metadata: EditorNodeMetadata(
                    confidence: node.confidence,
                    rationale: "Extracted from recording",
                    evidence: [
                        .init(type: .aiInferred, description: "Detected by semantic extractor", confidence: node.confidence)
                    ],
                    aiPromptContext: nil,
                    requiresReview: node.confidence < 0.5,
                    reviewReason: node.confidence < 0.5 ? "Low confidence — review before deploying" : nil
                ),
                confidence: node.confidence,
                executionType: mapExecType(node.executionType),
                isEditable: true, isUserModified: false, generatedByAI: true,
                apiReplacementAvailable: node.apiEquivalent,
                createdAt: Date(), updatedAt: Date()
            )
        }

        let editorEdges = graph.edges.map { edge in
            EditorEdge(
                id: edge.id,
                sourceNodeId: edge.sourceNodeId, sourcePortId: edge.sourcePortId,
                targetNodeId: edge.targetNodeId, targetPortId: edge.targetPortId,
                edgeType: mapEdgeType(edge.edgeType),
                label: edge.label, confidence: edge.confidence,
                metadata: EditorEdge.EdgeMetadata(
                    sourceEntity: edge.metadata.sourceEntity,
                    targetField: edge.metadata.targetField,
                    transformation: edge.metadata.transformation,
                    dataType: edge.metadata.dataType
                ),
                isUserCreated: false, createdAt: Date()
            )
        }

        let editorEntities = graph.detectedEntities.map { entity in
            EditorEntity(
                id: entity.id, name: entity.name, type: entity.type,
                sourceNodeId: entity.sourceNodeId, consumerNodeIds: entity.consumerNodeIds,
                fields: entity.fields
            )
        }

        let editorDataFlows = graph.dataFlowPaths.map { flow in
            EditorDataFlow(
                id: flow.id, description: flow.description,
                sourceNodeId: flow.sourceNodeId, sourceEntity: flow.sourceEntity,
                targetNodeId: flow.targetNodeId, targetField: flow.targetField,
                transformation: flow.transformation
            )
        }

        let editorIntegrations = graph.requiredIntegrations.map { integ in
            EditorIntegration(
                provider: integ.provider, reason: integ.reason,
                isConnected: integ.isConnected, requiredScopes: integ.requiredScopes,
                usedByNodeIds: integ.usedByNodeIds
            )
        }

        var editorGraph = EditorGraph(
            id: graph.id, version: 1,
            title: graph.title, description: graph.description,
            objective: graph.objective, domain: graph.domain,
            nodes: editorNodes, edges: editorEdges,
            entities: editorEntities.isEmpty ? nil : editorEntities,
            dataFlows: editorDataFlows.isEmpty ? nil : editorDataFlows,
            confidence: EditorGraphConfidence(
                nodeConfidence: graph.confidence.nodeConfidence,
                edgeConfidence: graph.confidence.edgeConfidence,
                coherenceScore: graph.confidence.coherenceScore,
                overallConfidence: graph.confidence.overallConfidence
            ),
            executionStrategy: EditorExecutionStrategy(
                primaryMode: graph.executionStrategy.primaryMode,
                cloudNodeCount: graph.executionStrategy.cloudNodeCount,
                desktopNodeCount: graph.executionStrategy.desktopNodeCount,
                apiReplacementsAvailable: graph.executionStrategy.apiReplacementsAvailable,
                cloudFeasible: graph.executionStrategy.cloudFeasible,
                cloudBlockers: graph.executionStrategy.cloudBlockers
            ),
            readiness: EditorReadiness(
                isReady: graph.automationReadiness.isReady,
                blockers: graph.automationReadiness.blockers,
                recommendations: graph.automationReadiness.recommendations
            ),
            requiredIntegrations: editorIntegrations,
            versions: [],
            aiEditHistory: [],
            createdAt: Date(), updatedAt: Date(),
            generatedBy: .ai
        )

        // Auto-layout
        GraphLayoutEngine.layout(&editorGraph)

        // Create initial version
        let v = VersionManager.createVersion(from: editorGraph, description: "Initial AI-generated workflow", createdBy: .ai)
        editorGraph.versions.append(v)

        return editorGraph
    }

    private static func mapCategory(_ cat: WorkflowNode.NodeCategory) -> EditorNode.EditorNodeCategory {
        switch cat {
        case .trigger: return .trigger
        case .dataSource: return .dataSource
        case .transformation: return .transformation
        case .decision: return .decision
        case .action: return .action
        case .desktop: return .desktop
        }
    }

    private static func mapExecType(_ et: WorkflowNode.ExecutionType) -> EditorNode.ExecutionType {
        switch et {
        case .cloud: return .cloud
        case .local: return .local
        case .desktop: return .desktop
        }
    }

    private static func mapEdgeType(_ et: WorkflowEdge.EdgeType) -> EditorEdge.EditorEdgeType {
        switch et {
        case .controlFlow: return .controlFlow
        case .dataFlow: return .dataFlow
        case .entityFlow: return .entityFlow
        case .dependency: return .dependency
        case .trigger: return .trigger
        }
    }

    private static func categoryColor(_ cat: EditorNode.EditorNodeCategory) -> EditorNode.NodeColor {
        switch cat {
        case .trigger: return .init(background: "#1a1a2e", border: "#eab308", accent: "#eab308")
        case .dataSource: return .init(background: "#1a1a2e", border: "#3b82f6", accent: "#3b82f6")
        case .transformation: return .init(background: "#1a1a2e", border: "#8b5cf6", accent: "#8b5cf6")
        case .decision: return .init(background: "#1a1a2e", border: "#f59e0b", accent: "#f59e0b")
        case .action: return .init(background: "#1a1a2e", border: "#22c55e", accent: "#22c55e")
        case .desktop: return .init(background: "#1a1a2e", border: "#6b7280", accent: "#6b7280")
        }
    }

    private static func iconForType(_ type: String) -> String {
        switch type {
        case "schedule_trigger": return "clock"
        case "manual_trigger": return "hand.tap"
        case "gmail_search": return "magnifyingglass"
        case "gmail_fetch": return "envelope.open"
        case "send_email": return "paperplane"
        case "spreadsheet_read": return "tablecells"
        case "append_sheet_row": return "plus.rectangle"
        case "extract_fields": return "scissors"
        case "condition": return "arrow.triangle.branch"
        case "website_fetch": return "globe"
        case "type_text": return "keyboard"
        case "click_ui_element": return "cursorarrow.click"
        case "open_application": return "app.badge"
        default: return "square"
        }
    }
}

// MARK: - ═══════════════════════════════════════════
// MARK: JSON Output (UI-Compatible)
// MARK: ═══════════════════════════════════════════

extension EditorGraph {
    /// Export in React Flow compatible format
    func toReactFlowJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    /// Export a simplified view for rendering engines
    func toRenderGraph() -> RenderGraph {
        RenderGraph(
            id: id,
            title: title,
            nodes: nodes.map { node in
                RenderGraph.RenderNode(
                    id: node.id,
                    type: node.type,
                    label: node.label,
                    category: node.category.rawValue,
                    position: RenderGraph.RenderPosition(x: node.position.x, y: node.position.y),
                    size: RenderGraph.RenderSize(width: node.size.width, height: node.size.height),
                    color: node.color,
                    icon: node.icon,
                    badge: node.badge,
                    confidence: node.confidence,
                    executionType: node.executionType.rawValue
                )
            },
            edges: edges.map { edge in
                RenderGraph.RenderEdge(
                    id: edge.id,
                    source: edge.sourceNodeId,
                    target: edge.targetNodeId,
                    sourcePort: edge.sourcePortId,
                    targetPort: edge.targetPortId,
                    type: edge.edgeType.rawValue,
                    label: edge.label
                )
            }
        )
    }
}

/// Minimal graph representation for visualization libraries
struct RenderGraph: Codable {
    let id: String
    let title: String
    let nodes: [RenderNode]
    let edges: [RenderEdge]

    struct RenderNode: Codable {
        let id: String
        let type: String
        let label: String
        let category: String
        let position: RenderPosition
        let size: RenderSize
        let color: EditorNode.NodeColor
        let icon: String
        let badge: EditorNode.NodeBadge?
        let confidence: Double
        let executionType: String
    }

    struct RenderEdge: Codable {
        let id: String
        let source: String
        let target: String
        let sourcePort: String?
        let targetPort: String?
        let type: String
        let label: String?
    }

    struct RenderPosition: Codable {
        let x: Double
        let y: Double
    }

    struct RenderSize: Codable {
        let width: Double
        let height: Double
    }
}
