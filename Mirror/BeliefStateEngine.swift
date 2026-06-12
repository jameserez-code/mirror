import Foundation

// MARK: ═══════════════════════════════════════════
// MARK: 1 — Belief State (Unified Probabilistic Model)
// MARK: ═══════════════════════════════════════════

/// The single probabilistic model of all workflow meaning.
/// All downstream systems project from this — nothing selects independently.
struct BeliefState: Codable {
    let id: String
    let sessionId: String
    var updatedAt: Date
    var version: Int                     // incremented on each update

    // A — Intent Beliefs
    var intentDistribution: IntentBeliefSpace

    // G — Goal Beliefs (goal-conditioned; precedes intent)
    var goalDistribution: GoalBeliefSpace

    // B — Entity Beliefs
    var entityBeliefs: EntityBeliefSpace

    // C — Workflow Structure Beliefs
    var structureBeliefs: StructureBeliefSpace

    // D — Strategy Suitability Beliefs
    var strategySuitability: StrategySuitabilitySpace

    // E — Context Anchors
    var context: BeliefContext

    // F — Global Uncertainty Metrics
    var metrics: BeliefMetrics
}

// MARK: — A: Intent Distribution

struct IntentBeliefSpace: Codable {
    /// Probability mass over core intent classes
    var coreIntentDistribution: [String: Double]  // intentClass → probability

    /// Multi-label sub-intents with independent probabilities
    var subIntents: [String: Double]              // e.g. "search" → 0.92, "compose" → 0.15

    /// Entropy of intent distribution
    var entropy: Double

    /// Top 3 intents with probabilities
    var topIntents: [WeightedIntent]

    /// How stable has this distribution been across updates?
    var stability: Double                         // 0-1, higher = more stable

    /// Was this derived from keyword, entity, or action evidence?
    var dominantEvidenceSource: EvidenceSource

    struct WeightedIntent: Codable {
        let objective: String
        let domain: String
        let probability: Double
        let evidence: [String]        // what supports this intent
    }

    enum EvidenceSource: String, Codable {
        case keywordDriven
        case entityDriven
        case actionDriven
        case hybrid
        case priorDominant        // unchanged from prior belief
    }
}

// MARK: — G: Goal Beliefs (conditions intent, entities, strategy)

struct GoalBeliefSpace: Codable {
    /// Probability distribution over goal types
    var goalDistribution: [String: Double]     // goalType → P(goal | evidence)

    /// Success conditions tied to the dominant goal
    var successConditions: [GoalSuccessCondition]

    /// Priority weights: what matters most?
    var priorityWeights: GoalPriorityWeights

    /// Entropy of goal distribution
    var entropy: Double

    /// How confident are we in the inferred goal?
    var confidence: Double

    /// Is the goal user-defined or inferred?
    var source: GoalSource

    enum GoalSource: String, Codable {
        case inferred
        case userDefined
        case blended
    }
}

struct GoalSuccessCondition: Codable {
    let condition: String          // e.g. "email_reply_received", "spreadsheet_row_updated"
    let description: String
    let measurable: Bool
    let targetLayer: String        // "execution", "entity", "intent"
}

struct GoalPriorityWeights: Codable {
    var accuracy: Double           // 0-1, how much does correctness matter?
    var speed: Double              // 0-1, how much does completion time matter?
    var completeness: Double       // 0-1, how much does covering all data matter?
    var safety: Double             // 0-1, how much does avoiding errors matter?
}

// MARK: — B: Entity Beliefs

struct EntityBeliefSpace: Codable {
    /// Each entity with its belief probability + field-level confidence
    var entities: [String: EntityBelief]          // entityId → belief

    /// Entity relationship probabilities
    var relationships: [String: RelationshipBelief] // "entityA→entityB" → belief

    /// Aggregate confidence
    var overallConfidence: Double

    /// Mapping origin probabilities (where did field mappings come from?)
    var mappingOriginDistribution: [String: Double] // "clipboard" → 0.6, "header" → 0.3, "inferred" → 0.1

    struct EntityBelief: Codable {
        var entityType: String
        var name: String
        var existenceProbability: Double           // does this entity exist?
        var fieldConfidences: [String: Double]     // fieldName → confidence
        var sourceApp: String
        var sourceConfidence: Double               // how reliable is the source?
    }

    struct RelationshipBelief: Codable {
        var sourceId: String
        var targetId: String
        var relationshipType: String               // "contains", "derives", "mapsTo"
        var probability: Double
    }
}

// MARK: — C: Workflow Structure Beliefs

struct StructureBeliefSpace: Codable {
    /// Each potential node with existence probability
    var nodes: [String: NodeBelief]               // nodeId → belief

    /// Each potential edge with existence probability
    var edges: [String: EdgeBelief]               // "source→target" → belief

    /// Execution path probabilities (ordered sequences)
    var pathProbabilities: [String: Double]        // "node1→node2→node3" → probability

    /// Graph entropy (higher = more uncertain structure)
    var structuralEntropy: Double

    /// Which nodes are considered certain (probability > 0.8)
    var certainNodes: [String]

    struct NodeBelief: Codable {
        var nodeType: String
        var label: String
        var existenceProbability: Double
        var orderingPrior: Double                  // position confidence
        var provider: String?
        var executionType: String?
        var confidenceUpdatedAt: Date
    }

    struct EdgeBelief: Codable {
        var sourceId: String
        var targetId: String
        var edgeType: String
        var existenceProbability: Double
    }
}

// MARK: — D: Strategy Suitability

struct StrategySuitabilitySpace: Codable {
    /// Per-strategy-vector expected reward
    var strategyScores: [String: StrategyBelief]   // fingerprint → belief

    /// Which strategy is currently recommended?
    var recommendedFingerprint: String?

    /// Strategy entropy (higher = more uncertain which strategy is best)
    var strategyEntropy: Double

    /// Average expected reward across all strategies
    var averageExpectedReward: Double

    struct StrategyBelief: Codable {
        var expectedReward: Double
        var sampleCount: Int
        var confidence: Double                     // how certain are we about this estimate?
        var lastUpdated: Date
        var isExploratory: Bool                    // was this selected for exploration?
    }
}

// MARK: — E: Context Anchors

struct BeliefContext: Codable {
    var clusterKey: String
    var providerMix: [String: Bool]                // provider → present
    var actionCount: Int
    var clipboardDensity: Double
    var textEntropy: Double
    var sessionDuration: Double
    var featureVector: [String: Double]             // normalized features
}

// MARK: — F: Global Metrics

struct BeliefMetrics: Codable {
    var overallEntropy: Double
    var convergenceRate: Double
    var stabilityScore: Double
    var confidenceTrend: String
    var updatesSinceLastConvergence: Int
    var isConverged: Bool
    var convergenceThreshold: Double = 0.25

    // Goal alignment
    var goalAlignmentScore: Double            // how well interpretation aligns with goal
    var goalDriftDetected: Bool               // has the goal shifted significantly?
    var interpretationErrorDecomposition: ErrorDecomposition?

    struct ErrorDecomposition: Codable {
        var goalError: Double                  // wrong goal inferred
        var interpretationError: Double         // right goal, wrong interpretation
        var executionError: Double              // right interpretation, wrong execution
    }
}

// MARK: ═══════════════════════════════════════════
// MARK: 2 — Belief State Engine
// MARK: ═══════════════════════════════════════════

struct BeliefStateEngine {

    // MARK: — Initialize

    static func initialize(sessionId: String) -> BeliefState {
        BeliefState(
            id: "belief_\(sessionId)",
            sessionId: sessionId,
            updatedAt: Date(),
            version: 0,
            intentDistribution: IntentBeliefSpace(
                coreIntentDistribution: [:],
                subIntents: [:],
                entropy: 1.0,
                topIntents: [],
                stability: 0,
                dominantEvidenceSource: .hybrid
            ),
            goalDistribution: GoalBeliefSpace(
                goalDistribution: [:],
                successConditions: [],
                priorityWeights: GoalPriorityWeights(accuracy: 0.5, speed: 0.5, completeness: 0.5, safety: 0.5),
                entropy: 1.0,
                confidence: 0,
                source: .inferred
            ),
            entityBeliefs: EntityBeliefSpace(
                entities: [:], relationships: [:],
                overallConfidence: 0, mappingOriginDistribution: [:]
            ),
            structureBeliefs: StructureBeliefSpace(
                nodes: [:], edges: [:], pathProbabilities: [:],
                structuralEntropy: 1.0, certainNodes: []
            ),
            strategySuitability: StrategySuitabilitySpace(
                strategyScores: [:], recommendedFingerprint: nil,
                strategyEntropy: 1.0, averageExpectedReward: 0
            ),
            context: BeliefContext(
                clusterKey: "initial", providerMix: [:], actionCount: 0,
                clipboardDensity: 0, textEntropy: 0, sessionDuration: 0,
                featureVector: [:]
            ),
            metrics: BeliefMetrics(
                overallEntropy: 1.0, convergenceRate: 0, stabilityScore: 0,
                confidenceTrend: "stable", updatesSinceLastConvergence: 0, isConverged: false,
                goalAlignmentScore: 0, goalDriftDetected: false, interpretationErrorDecomposition: nil
            )
        )
    }

    // MARK: — Per-Event-Batch Update

    static func update(
        _ state: inout BeliefState,
        events: [EventTapManager.CapturedEvent],
        partialActions: [SemanticAction] = [],
        partialArtifacts: [ExtractedArtifact] = [],
        evaluation: DebugBundle? = nil
    ) {
        state.version += 1
        state.updatedAt = Date()
        let prevMetrics = state.metrics

        // 1. Update context anchors
        updateContext(&state.context, events: events, actions: partialActions)

        // 1a. Infer goal distribution (conditions everything below)
        updateGoalBeliefs(&state.goalDistribution, actions: partialActions, artifacts: partialArtifacts, context: state.context)

        // 2. Update intent beliefs (now goal-conditioned)
        updateIntentBeliefs(&state.intentDistribution, actions: partialActions, artifacts: partialArtifacts, goal: state.goalDistribution, state: state)

        // 3. Update entity beliefs
        updateEntityBeliefs(&state.entityBeliefs, actions: partialActions, artifacts: partialArtifacts)

        // 4. Update structure beliefs
        updateStructureBeliefs(&state.structureBeliefs, actions: partialActions)

        // 5. Update strategy suitability
        updateStrategySuitability(&state.strategySuitability, context: state.context, actions: partialActions)

        // 6. Apply evaluation feedback if available
        if let eval = evaluation {
            applyEvaluationFeedback(&state, evaluation: eval)
        }

        // 7. Update global metrics
        updateMetrics(&state.metrics, state: state, prevMetrics: prevMetrics)
    }

    // MARK: — Context Update

    private static func updateContext(_ ctx: inout BeliefContext, events: [EventTapManager.CapturedEvent], actions: [SemanticAction]) {
        let providers = Set(actions.map(\.provider))
        ctx.providerMix = [
            "gmail": providers.contains("gmail"),
            "sheets": providers.contains("sheets"),
            "desktop": providers.contains(where: { !["gmail","sheets","browser","chrome"].contains($0) }),
            "browser": providers.contains("browser") || providers.contains("chrome")
        ]
        ctx.actionCount = actions.count
        ctx.clipboardDensity = actions.count > 0 ? Double(events.filter { $0.type == "clipboardChange" }.count) / Double(actions.count) : 0
        ctx.textEntropy = actions.compactMap { $0.payload.typedText }.joined().count > 0 ? 0.5 : 0.1
        ctx.sessionDuration = (events.last?.timestamp ?? 0) - (events.first?.timestamp ?? 0)
        ctx.clusterKey = buildClusterKey(from: ctx)
        ctx.featureVector = [
            "clipboardDensity": ctx.clipboardDensity,
            "textEntropy": ctx.textEntropy,
            "actionCount": Double(ctx.actionCount),
            "sessionDuration": ctx.sessionDuration
        ]
    }

    private static func buildClusterKey(from ctx: BeliefContext) -> String {
        var parts: [String] = []
        if ctx.providerMix["gmail"] == true && ctx.providerMix["sheets"] == true { parts.append("pm_gmail+sheets") }
        else if ctx.providerMix["sheets"] == true { parts.append("pm_sheets") }
        else if ctx.providerMix["gmail"] == true { parts.append("pm_gmail") }
        else if ctx.providerMix["browser"] == true { parts.append("pm_browser") }
        else { parts.append("pm_other") }

        let cd = ctx.clipboardDensity > 0.5 ? "high" : ctx.clipboardDensity > 0.2 ? "med" : "low"
        parts.append("cd_\(cd)")
        let ac = ctx.actionCount > 5 ? "high" : ctx.actionCount > 3 ? "med" : "low"
        parts.append("ac_\(ac)")
        return parts.joined(separator: "|")
    }

    // MARK: — Goal Inference

    private static func updateGoalBeliefs(
        _ goal: inout GoalBeliefSpace,
        actions: [SemanticAction],
        artifacts: [ExtractedArtifact],
        context: BeliefContext
    ) {
        let evidence = extractGoalEvidence(actions: actions, artifacts: artifacts, context: context)
        let learningRate: Double = 0.15
        let priorWeight = 1.0 - learningRate

        for (goalType, evidenceVal) in evidence {
            let prior = goal.goalDistribution[goalType] ?? 0.10
            goal.goalDistribution[goalType] = prior * priorWeight + evidenceVal * learningRate
        }
        for key in goal.goalDistribution.keys where evidence[key] == nil {
            goal.goalDistribution[key]! *= 0.95
        }
        let sum = goal.goalDistribution.values.reduce(0, +)
        if sum > 0 { for key in goal.goalDistribution.keys { goal.goalDistribution[key]! /= sum } }

        goal.entropy = -goal.goalDistribution.values.reduce(0) { s, p in p > 0 ? s + p * log(p) : s }
        goal.confidence = goal.entropy < 0.3 ? 0.9 : goal.entropy < 0.6 ? 0.6 : 0.3
        goal.successConditions = generateSuccessConditions(for: goal.goalDistribution.max(by: { $0.value < $1.value })?.key ?? "", actions: actions, artifacts: artifacts, context: context)
        goal.priorityWeights = goalPriorityWeights(for: goal.goalDistribution.max(by: { $0.value < $1.value })?.key ?? "")
        goal.source = .inferred
    }

    private static func extractGoalEvidence(actions: [SemanticAction], artifacts: [ExtractedArtifact], context: BeliefContext) -> [String: Double] {
        var evidence: [String: Double] = [:]
        let text = actions.compactMap { $0.payload.typedText ?? $0.payload.query ?? $0.payload.subject }.joined(separator: " ").lowercased()
        if text.contains("search") || text.contains("find") || text.contains("lookup") { evidence["information_extraction"] = (evidence["information_extraction"] ?? 0) + 0.25 }
        if context.clipboardDensity > 0.3 { evidence["information_extraction"] = (evidence["information_extraction"] ?? 0) + 0.20 }
        if actions.contains(where: { $0.action == "extract_data" || $0.action == "copy_clipboard" }) { evidence["information_extraction"] = (evidence["information_extraction"] ?? 0) + 0.20 }
        let uniqueProviders = Set(actions.map(\.provider))
        if uniqueProviders.count >= 2 { evidence["data_synchronization"] = (evidence["data_synchronization"] ?? 0) + 0.30 }
        if context.providerMix["gmail"] == true && context.providerMix["sheets"] == true { evidence["data_synchronization"] = (evidence["data_synchronization"] ?? 0) + 0.25 }
        if text.contains("download") || text.contains("attach") || text.contains("file") || text.contains("pdf") { evidence["document_processing"] = (evidence["document_processing"] ?? 0) + 0.30 }
        if text.contains("report") || text.contains("weekly") || text.contains("summary") || text.contains("digest") { evidence["reporting_automation"] = (evidence["reporting_automation"] ?? 0) + 0.28 }
        if actions.contains(where: { $0.action == "gmail_send" || $0.action == "send_email" }) { evidence["outreach_conversion"] = (evidence["outreach_conversion"] ?? 0) + 0.30 }
        if text.contains("reply") || text.contains("followup") || text.contains("outreach") { evidence["outreach_conversion"] = (evidence["outreach_conversion"] ?? 0) + 0.20 }
        let totalEvidence = evidence.values.reduce(0, +)
        if totalEvidence > 0 { for key in evidence.keys { evidence[key] = min(evidence[key]! / totalEvidence, 0.95) } }
        if evidence.isEmpty { evidence["general_automation"] = 0.50 }
        return evidence
    }

    private static func generateSuccessConditions(for goalType: String, actions: [SemanticAction], artifacts: [ExtractedArtifact], context: BeliefContext) -> [GoalSuccessCondition] {
        switch goalType {
        case "information_extraction": return [.init(condition: "data_field_extracted", description: "Target data extracted from source", measurable: true, targetLayer: "entity"), .init(condition: "clipboard_capture_verified", description: "Extracted value matches expected format", measurable: true, targetLayer: "entity")]
        case "data_synchronization": return [.init(condition: "spreadsheet_row_updated", description: "Data written to destination sheet", measurable: true, targetLayer: "execution"), .init(condition: "source_destination_match", description: "Source and destination values match", measurable: true, targetLayer: "entity")]
        case "outreach_conversion": return [.init(condition: "email_reply_received", description: "Recipient responded to outreach", measurable: true, targetLayer: "execution"), .init(condition: "personalization_applied", description: "Message tailored to recipient context", measurable: false, targetLayer: "intent")]
        case "reporting_automation": return [.init(condition: "report_generated", description: "Report output produced successfully", measurable: true, targetLayer: "execution"), .init(condition: "data_completeness", description: "All required data sources included", measurable: true, targetLayer: "intent")]
        case "document_processing": return [.init(condition: "file_download_completed", description: "File successfully downloaded", measurable: true, targetLayer: "execution"), .init(condition: "document_fields_extracted", description: "Structured fields extracted from document", measurable: true, targetLayer: "entity")]
        default: return [.init(condition: "workflow_completed", description: "All steps executed without error", measurable: true, targetLayer: "execution")]
        }
    }

    private static func goalPriorityWeights(for goalType: String) -> GoalPriorityWeights {
        switch goalType {
        case "information_extraction": return .init(accuracy: 0.90, speed: 0.50, completeness: 0.85, safety: 0.40)
        case "outreach_conversion": return .init(accuracy: 0.50, speed: 0.70, completeness: 0.60, safety: 0.80)
        case "data_synchronization": return .init(accuracy: 0.85, speed: 0.40, completeness: 0.90, safety: 0.50)
        case "reporting_automation": return .init(accuracy: 0.70, speed: 0.40, completeness: 0.90, safety: 0.30)
        case "document_processing": return .init(accuracy: 0.75, speed: 0.50, completeness: 0.60, safety: 0.60)
        default: return .init(accuracy: 0.60, speed: 0.60, completeness: 0.60, safety: 0.60)
        }
    }

    // MARK: — Intent Belief Update (Goal-Conditioned)

    private static func updateIntentBeliefs(
        _ intent: inout IntentBeliefSpace,
        actions: [SemanticAction],
        artifacts: [ExtractedArtifact],
        goal: GoalBeliefSpace,
        state: BeliefState
    ) {
        let newEvidence = extractIntentEvidence(actions: actions, artifacts: artifacts)
        let learningRate: Double = 0.15
        let priorWeight = 1.0 - learningRate

        // Goal-conditioned bias: intents aligned with dominant goal get boosted
        let dominantGoal = goal.goalDistribution.max(by: { $0.value < $1.value })?.key ?? ""
        let goalBiasedEvidence = applyGoalBias(to: newEvidence, goal: dominantGoal)

        // Update existing intents + add new ones
        for (intentClass, evidence) in goalBiasedEvidence {
            let prior = intent.coreIntentDistribution[intentClass] ?? 0.10  // weak uniform prior
            intent.coreIntentDistribution[intentClass] = prior * priorWeight + evidence * learningRate
        }

        // Decay intents not seen in this update
        for key in intent.coreIntentDistribution.keys where newEvidence[key] == nil {
            intent.coreIntentDistribution[key]! *= 0.95
        }

        // Renormalize
        let sum = intent.coreIntentDistribution.values.reduce(0, +)
        if sum > 0 {
            for key in intent.coreIntentDistribution.keys {
                intent.coreIntentDistribution[key]! /= sum
            }
        }

        // Top intents
        intent.topIntents = intent.coreIntentDistribution
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { IntentBeliefSpace.WeightedIntent(
                objective: $0.key, domain: inferDomain(for: $0.key),
                probability: $0.value, evidence: ["action_sequence"]
            )}

        // Entropy
        intent.entropy = -intent.coreIntentDistribution.values.reduce(0) { sum, p in
            p > 0 ? sum + p * log(p) : sum
        }

        // Stability
        intent.stability = intent.entropy < 0.3 ? 0.9 : intent.entropy < 0.6 ? 0.5 : 0.2

        // Evidence source
        let keywordCount = actions.filter { ($0.payload.typedText?.count ?? 0) > 5 }.count
        let entityCount = artifacts.count
        intent.dominantEvidenceSource = keywordCount > entityCount ? .keywordDriven
            : entityCount > 0 ? .entityDriven
            : .actionDriven
    }

    private static func extractIntentEvidence(
        actions: [SemanticAction],
        artifacts: [ExtractedArtifact]
    ) -> [String: Double] {
        var evidence: [String: Double] = [:]
        let text = actions.compactMap { $0.payload.typedText ?? $0.payload.query ?? $0.payload.subject }.joined(separator: " ").lowercased()

        // Invoice-related
        if text.contains("invoice") || text.contains("bill") || text.contains("payment") || text.contains("vendor") {
            evidence["invoice_processing"] = 0.82
        }
        if text.contains("receipt") || text.contains("expense") || text.contains("spend") {
            evidence["expense_tracking"] = 0.78
        }

        // Lead/CRM
        if text.contains("lead") || text.contains("contact") || text.contains("linkedin") {
            evidence["lead_generation"] = 0.80
        }
        if text.contains("crm") || text.contains("customer") || text.contains("client") {
            evidence["crm_management"] = 0.76
        }

        // Reporting
        if text.contains("report") || text.contains("weekly") || text.contains("summary") || text.contains("digest") {
            evidence["reporting"] = 0.74
        }

        // Data transfer
        if actions.contains(where: { $0.provider == "gmail" }) && actions.contains(where: { $0.provider == "sheets" }) {
            evidence["email_to_sheet"] = 0.70
        }

        // File operations
        if text.contains("download") || text.contains("attach") || text.contains("file") || text.contains("pdf") {
            evidence["file_management"] = 0.65
        }

        // Generic fallback
        if evidence.isEmpty {
            evidence["generic_workflow"] = 0.50
        }

        return evidence
    }

    private static func applyGoalBias(to evidence: [String: Double], goal: String) -> [String: Double] {
        let goalIntentMap: [String: [String]] = [
            "information_extraction": ["invoice_processing", "expense_tracking", "lead_generation"],
            "data_synchronization": ["email_to_sheet", "crm_management"],
            "outreach_conversion": ["lead_generation", "crm_management"],
            "reporting_automation": ["reporting", "email_to_sheet"],
            "document_processing": ["file_management", "invoice_processing"],
        ]
        var biased = evidence
        let boost = 0.08
        if let aligned = goalIntentMap[goal] {
            for intent in aligned { biased[intent] = (biased[intent] ?? 0) + boost }
        }
        return biased
    }

    private static func inferDomain(for intent: String) -> String {
        switch intent {
        case let s where s.contains("invoice"): return "accounts_payable"
        case let s where s.contains("expense"): return "expense_management"
        case let s where s.contains("lead"): return "lead_generation"
        case let s where s.contains("crm"): return "crm"
        case let s where s.contains("report"): return "reporting"
        case let s where s.contains("file"): return "file_management"
        default: return "general"
        }
    }

    // MARK: — Entity Belief Update (Exponential Smoothing)

    private static func updateEntityBeliefs(
        _ entities: inout EntityBeliefSpace,
        actions: [SemanticAction],
        artifacts: [ExtractedArtifact]
    ) {
        let smoothing: Double = 0.2

        for artifact in artifacts {
            var belief = entities.entities[artifact.id] ?? EntityBeliefSpace.EntityBelief(
                entityType: artifact.artifactType, name: artifact.title,
                existenceProbability: 0.5, fieldConfidences: [:],
                sourceApp: artifact.sourceApp, sourceConfidence: artifact.confidence
            )
            // Update existence probability
            belief.existenceProbability = belief.existenceProbability * (1 - smoothing) + artifact.confidence * smoothing
            // Update field confidences
            for field in artifact.fields {
                let prior = belief.fieldConfidences[field.name] ?? 0.5
                belief.fieldConfidences[field.name] = prior * (1 - smoothing) + 1.0 * smoothing
            }
            entities.entities[artifact.id] = belief
        }

        // Decay entities not seen
        for key in entities.entities.keys where !artifacts.contains(where: { $0.id == key }) {
            entities.entities[key]?.existenceProbability *= 0.95
        }

        entities.overallConfidence = entities.entities.isEmpty ? 0 : entities.entities.values.map(\.existenceProbability).reduce(0, +) / Double(entities.entities.count)
    }

    // MARK: — Structure Belief Update

    private static func updateStructureBeliefs(
        _ structure: inout StructureBeliefSpace,
        actions: [SemanticAction]
    ) {
        let smoothing: Double = 0.2

        for action in actions {
            var node = structure.nodes[action.id] ?? StructureBeliefSpace.NodeBelief(
                nodeType: action.action, label: action.description,
                existenceProbability: 0.5, orderingPrior: Double(actions.firstIndex(where: { $0.id == action.id }) ?? 0),
                provider: action.provider, executionType: action.executionType,
                confidenceUpdatedAt: Date()
            )
            node.existenceProbability = node.existenceProbability * (1 - smoothing) + action.confidence * smoothing
            structure.nodes[action.id] = node
        }

        // Decay unseen nodes
        for key in structure.nodes.keys where !actions.contains(where: { $0.id == key }) {
            structure.nodes[key]?.existenceProbability *= 0.95
        }

        // Certain nodes
        structure.certainNodes = structure.nodes.filter { $0.value.existenceProbability > 0.8 }.map(\.key)

        // Structural entropy
        let probs = structure.nodes.values.map(\.existenceProbability)
        structure.structuralEntropy = probs.isEmpty ? 1.0 : -probs.reduce(0) { sum, p in p > 0 ? sum + p * log(p) : sum } / Double(probs.count)
    }

    // MARK: — Strategy Suitability Update (Reward-Weighted)

    private static func updateStrategySuitability(
        _ strategy: inout StrategySuitabilitySpace,
        context: BeliefContext,
        actions: [SemanticAction]
    ) {
        // Seed initial strategy scores if empty
        if strategy.strategyScores.isEmpty {
            seedStrategyScores(&strategy, context: context)
        }

        // Boost strategies that match context characteristics
        for (fingerprint, var belief) in strategy.strategyScores {
            let boost = computeStrategyContextBoost(fingerprint: fingerprint, context: context, actions: actions)
            belief.expectedReward = min(belief.expectedReward * 0.95 + boost * 0.05, 1.0)
            strategy.strategyScores[fingerprint] = belief
        }

        // Recommend best
        let best = strategy.strategyScores.max(by: { $0.value.expectedReward < $1.value.expectedReward })
        strategy.recommendedFingerprint = best?.key

        // Strategy entropy
        let scores = strategy.strategyScores.values.map(\.expectedReward)
        let sum = scores.reduce(0, +)
        strategy.strategyEntropy = sum > 0 ? -scores.reduce(0) { s, p in
            let norm = p / sum
            return norm > 0 ? s + norm * log(norm) : s
        } : 1.0
        strategy.averageExpectedReward = scores.isEmpty ? 0 : sum / Double(scores.count)
    }

    private static func seedStrategyScores(_ strategy: inout StrategySuitabilitySpace, context: BeliefContext) {
        for intentStrat in StrategySet.IntentStrategy.allCases.prefix(2) {
            for entityStrat in StrategySet.EntityResolutionStrategy.allCases.prefix(2) {
                for graphStrat in StrategySet.GraphConstructionStrategy.allCases.prefix(2) {
                    let fp = "\(intentStrat.rawValue)|\(entityStrat.rawValue)|\(graphStrat.rawValue)|balanced|fuzzyMapping"
                    strategy.strategyScores[fp] = StrategySuitabilitySpace.StrategyBelief(
                        expectedReward: 0.5, sampleCount: 0, confidence: 0.3,
                        lastUpdated: Date(), isExploratory: false
                    )
                }
            }
        }
    }

    private static func computeStrategyContextBoost(fingerprint: String, context: BeliefContext, actions: [SemanticAction]) -> Double {
        var boost: Double = 0.5
        if fingerprint.contains("headerWeighted") && context.providerMix["sheets"] == true { boost += 0.10 }
        if fingerprint.contains("dataflowFirst") && context.clipboardDensity > 0.5 { boost += 0.08 }
        if fingerprint.contains("keywordFirst") && context.textEntropy < 0.3 { boost += 0.05 }
        if fingerprint.contains("conservativeMerge") && actions.count > 5 { boost += 0.06 }
        return min(boost, 1.0)
    }

    // MARK: — Evaluation Feedback (belief correction)

    private static func applyEvaluationFeedback(_ state: inout BeliefState, evaluation: DebugBundle) {
        let reward = PolicyReward.compute(from: evaluation)

        // Correct intent distribution
        for (intentClass, var prob) in state.intentDistribution.coreIntentDistribution {
            let correction = reward.totalReward > 0.7 ? 0.02 : -0.03
            prob = max(0.01, min(prob + correction, 0.99))
            state.intentDistribution.coreIntentDistribution[intentClass] = prob
        }

        // Correct entity confidences
        for correction in evaluation.groundTruth.userCorrections where correction.targetLayer == .entity {
            if var entity = state.entityBeliefs.entities[correction.targetId] {
                entity.fieldConfidences[correction.field] = max(0.1, entity.fieldConfidences[correction.field, default: 0.5] - 0.15)
                state.entityBeliefs.entities[correction.targetId] = entity
            }
        }

        // Correct strategy suitability
        if let recommendedFp = state.strategySuitability.recommendedFingerprint,
           var belief = state.strategySuitability.strategyScores[recommendedFp] {
            belief.expectedReward = belief.expectedReward * 0.8 + reward.totalReward * 0.2
            belief.sampleCount += 1
            belief.confidence = min(1.0, Double(belief.sampleCount) / 10.0)
            state.strategySuitability.strategyScores[recommendedFp] = belief
        }

        // Decompose error: goal error vs interpretation error vs execution error
        let entityCorrect = reward.components.entityMappingAccuracy
        let intentCorrect = reward.components.intentAccuracy
        let execOK = reward.components.executionSuccess

        let goalError = 1.0 - state.goalDistribution.confidence
        let interpretationError = max(0, 1.0 - (entityCorrect * 0.6 + intentCorrect * 0.4))
        let executionError = max(0, 1.0 - execOK)

        state.metrics.interpretationErrorDecomposition = BeliefMetrics.ErrorDecomposition(
            goalError: goalError, interpretationError: interpretationError, executionError: executionError
        )
        state.metrics.goalDriftDetected = abs(state.goalDistribution.entropy - (1.0 - state.goalDistribution.confidence)) > 0.3
    }

    // MARK: — Global Metrics Update

    private static func updateMetrics(_ metrics: inout BeliefMetrics, state: BeliefState, prevMetrics: BeliefMetrics) {
        // Overall entropy: weighted composite of all belief entropies
        metrics.overallEntropy =
            state.intentDistribution.entropy * 0.35 +
            state.structureBeliefs.structuralEntropy * 0.30 +
            state.strategySuitability.strategyEntropy * 0.20 +
            (1 - state.entityBeliefs.overallConfidence) * 0.15

        // Stability: has entropy changed significantly?
        let entropyDelta = abs(metrics.overallEntropy - prevMetrics.overallEntropy)
        metrics.stabilityScore = max(0, 1.0 - entropyDelta * 3.0)

        // Convergence rate
        metrics.convergenceRate = prevMetrics.overallEntropy - metrics.overallEntropy

        // Trend
        if metrics.convergenceRate > 0.05 { metrics.confidenceTrend = "converging" }
        else if metrics.convergenceRate < -0.05 { metrics.confidenceTrend = "diverging" }
        else { metrics.confidenceTrend = "stable" }

        // Converged?
        metrics.isConverged = metrics.overallEntropy < metrics.convergenceThreshold
        if !metrics.isConverged { metrics.updatesSinceLastConvergence += 1 }
        else { metrics.updatesSinceLastConvergence = 0 }

        // Goal alignment: how well does intent align with goal?
        let dominantGoal = state.goalDistribution.goalDistribution.max(by: { $0.value < $1.value })?.key ?? ""
        metrics.goalAlignmentScore = computeGoalAlignment(goal: dominantGoal, intentDistribution: state.intentDistribution)
    }

    private static func computeGoalAlignment(goal: String, intentDistribution: IntentBeliefSpace) -> Double {
        let goalIntentMap: [String: [String]] = [
            "information_extraction": ["invoice_processing", "expense_tracking", "lead_generation"],
            "data_synchronization": ["email_to_sheet", "crm_management"],
            "outreach_conversion": ["lead_generation", "crm_management"],
            "reporting_automation": ["reporting", "email_to_sheet"],
            "document_processing": ["file_management", "invoice_processing"],
        ]
        guard let aligned = goalIntentMap[goal] else { return 0.5 }
        let alignedProbability = aligned.map { intentDistribution.coreIntentDistribution[$0] ?? 0 }.reduce(0, +)
        let totalProb = intentDistribution.coreIntentDistribution.values.reduce(0, +)
        return totalProb > 0 ? alignedProbability / totalProb : 0.5
    }

    // MARK: ═══════════════════════════════════════════
    // MARK: 3 — Projection Functions (Belief → Decision)
    // MARK: ═══════════════════════════════════════════

    /// Project the most probable intent from belief state
    static func projectIntent(from state: BeliefState) -> WorkflowIntent? {
        guard let top = state.intentDistribution.topIntents.first else { return nil }
        return WorkflowIntent(
            objective: top.objective,
            domain: top.domain,
            description: "Belief-projected: \(top.objective)",
            confidence: top.probability,
            triggerPattern: state.strategySuitability.strategyEntropy < 0.3 ? "0 9 * * 1-5" : "manual",
            frequency: state.strategySuitability.strategyEntropy < 0.3 ? "daily" : "on_demand",
            estimatedDuration: Double(state.context.actionCount) * 3.0
        )
    }

    /// Project entity nodes from belief state
    static func projectEntities(from state: BeliefState) -> [EntityNode] {
        state.entityBeliefs.entities.compactMap { (id, belief) in
            guard belief.existenceProbability > 0.3 else { return nil }
            return EntityNode(
                id: id, entityType: .init(rawValue: belief.entityType),
                category: belief.entityType.contains("sheet") || belief.entityType.contains("email") ? .document : .businessObject,
                name: belief.name,
                source: .init(application: belief.sourceApp, url: nil, artifactId: id, extractionMethod: "belief_projection"),
                confidence: belief.existenceProbability,
                fields: belief.fieldConfidences.map { .init(name: $0.key, value: "", dataType: .freeText, confidence: $0.value, extractedFrom: "belief", alternatives: nil) },
                provenanceEvents: []
            )
        }
    }

    /// Project workflow graph from belief state
    static func projectGraph(from state: BeliefState) -> (nodes: [WorkflowNode], edges: [WorkflowEdge]) {
        let nodes = state.structureBeliefs.nodes.compactMap { (id, belief) -> WorkflowNode? in
            guard belief.existenceProbability > 0.3 else { return nil }
            return WorkflowNode(
                id: id, type: .init(rawValue: belief.nodeType), category: .action,
                label: belief.label, confidence: belief.existenceProbability,
                provider: belief.provider, executionType: belief.executionType == "cloud" ? .cloud : .desktop,
                apiEquivalent: nil, position: nil,
                metadata: .init(), inputPorts: [], outputPorts: []
            )
        }
        let edges = state.structureBeliefs.edges.compactMap { (key, belief) -> WorkflowEdge? in
            guard belief.existenceProbability > 0.3 else { return nil }
            return WorkflowEdge(
                id: key, sourceNodeId: belief.sourceId, sourcePortId: nil,
                targetNodeId: belief.targetId, targetPortId: nil,
                edgeType: .controlFlow, confidence: belief.existenceProbability, label: nil,
                metadata: .init()
            )
        }
        return (nodes, edges)
    }

    /// Project the recommended strategy (goal-conditioned)
    static func projectStrategy(from state: BeliefState) -> StrategySet {
        guard let fp = state.strategySuitability.recommendedFingerprint,
              let belief = state.strategySuitability.strategyScores[fp] else {
            return .default
        }

        // Goal-aware biasing
        let priority = state.goalDistribution.priorityWeights

        // Adjust strategy based on goal priorities
        if priority.accuracy > 0.8 {
            return .init(intentStrategy: .entityFirst, entityStrategy: .headerWeighted, graphStrategy: .dataflowFirst, extractionSensitivity: .highPrecision, providerStrategy: .strictMapping, explorationTag: belief.isExploratory ? "explore" : nil)
        }
        if priority.speed > 0.7 {
            return .init(intentStrategy: .keywordFirst, entityStrategy: .extractionHeavy, graphStrategy: .minimalChain, extractionSensitivity: .highRecall, providerStrategy: .fuzzyMapping, explorationTag: nil)
        }
        if priority.completeness > 0.8 {
            return .init(intentStrategy: .hybridBalanced, entityStrategy: .extractionHeavy, graphStrategy: .hybridGraph, extractionSensitivity: .highRecall, providerStrategy: .fallbackEnabled, explorationTag: nil)
        }

        let parts = fp.components(separatedBy: "|")
        return StrategySet(
            intentStrategy: StrategySet.IntentStrategy(rawValue: parts[safe: 0] ?? "hybridBalanced") ?? .hybridBalanced,
            entityStrategy: StrategySet.EntityResolutionStrategy(rawValue: parts[safe: 1] ?? "balancedMerge") ?? .balancedMerge,
            graphStrategy: StrategySet.GraphConstructionStrategy(rawValue: parts[safe: 2] ?? "hybridGraph") ?? .hybridGraph,
            extractionSensitivity: StrategySet.ExtractionSensitivity(rawValue: parts[safe: 3] ?? "balanced") ?? .balanced,
            providerStrategy: StrategySet.ProviderInterpretationStrategy(rawValue: parts[safe: 4] ?? "fuzzyMapping") ?? .fuzzyMapping,
            explorationTag: belief.isExploratory ? "explore" : nil
        )
    }

    // MARK: ═══════════════════════════════════════════
    // MARK: 4 — Belief State Snapshot (execution engine input)
    // MARK: ═══════════════════════════════════════════

    static func snapshot(from state: BeliefState) -> BeliefStateSnapshot {
        let dominantGoal = state.goalDistribution.goalDistribution.max(by: { $0.value < $1.value })
        return BeliefStateSnapshot(
            sessionId: state.sessionId,
            version: state.version,
            converged: state.metrics.isConverged,
            overallEntropy: state.metrics.overallEntropy,
            projectedIntent: projectIntent(from: state).map { BeliefStateSnapshot.ProjectedIntent(objective: $0.objective, domain: $0.domain, confidence: $0.confidence) },
            projectedGoal: dominantGoal.map { BeliefStateSnapshot.ProjectedGoal(type: $0.key, confidence: $0.value) },
            goalAlignment: state.metrics.goalAlignmentScore,
            goalDriftDetected: state.metrics.goalDriftDetected,
            errorDecomposition: state.metrics.interpretationErrorDecomposition,
            projectedEntityCount: state.entityBeliefs.entities.filter { $0.value.existenceProbability > 0.5 }.count,
            projectedNodeCount: state.structureBeliefs.nodes.filter { $0.value.existenceProbability > 0.5 }.count,
            recommendedStrategy: projectStrategy(from: state).fingerprint,
            strategyConfidence: state.strategySuitability.strategyScores[state.strategySuitability.recommendedFingerprint ?? ""]?.confidence ?? 0,
            topIntents: state.intentDistribution.topIntents.prefix(3).map { BeliefStateSnapshot.ProjectedIntent(objective: $0.objective, domain: $0.domain, confidence: $0.probability) },
            priorityWeights: state.goalDistribution.priorityWeights,
            successConditions: state.goalDistribution.successConditions,
            stability: state.metrics.stabilityScore,
            readiness: state.metrics.isConverged ? "ready" : "uncertain"
        )
    }
}

// MARK: — Belief State Snapshot

struct BeliefStateSnapshot: Codable {
    let sessionId: String
    let version: Int
    let converged: Bool
    let overallEntropy: Double
    let projectedIntent: ProjectedIntent?
    let projectedGoal: ProjectedGoal?
    let goalAlignment: Double
    let goalDriftDetected: Bool
    let errorDecomposition: BeliefMetrics.ErrorDecomposition?
    let projectedEntityCount: Int
    let projectedNodeCount: Int
    let recommendedStrategy: String
    let strategyConfidence: Double
    let topIntents: [ProjectedIntent]
    let priorityWeights: GoalPriorityWeights
    let successConditions: [GoalSuccessCondition]
    let stability: Double
    let readiness: String

    struct ProjectedIntent: Codable {
        let objective: String
        let domain: String
        let confidence: Double
    }

    struct ProjectedGoal: Codable {
        let type: String
        let confidence: Double
    }

    func summary() -> String {
        var lines: [String] = []
        lines.append("BeliefState v\(version) [\(readiness)]")
        lines.append("  Entropy: \(String(format: "%.2f", overallEntropy)) | Stability: \(String(format: "%.2f", stability))")
        if let intent = projectedIntent {
            lines.append("  Intent: \(intent.objective) (\(intent.domain)) @ \(String(format: "%.0f", intent.confidence * 100))%")
        }
        if let goal = projectedGoal {
            lines.append("  Goal: \(goal.type) @ \(String(format: "%.0f", goal.confidence * 100))% | Alignment: \(String(format: "%.0f", goalAlignment * 100))%")
        }
        if let errors = errorDecomposition {
            lines.append("  Errors: goal=\(String(format: "%.2f", errors.goalError)) interpret=\(String(format: "%.2f", errors.interpretationError)) exec=\(String(format: "%.2f", errors.executionError))")
        }
        if goalDriftDetected { lines.append("  ⚠ Goal drift detected") }
        lines.append("  Entities: \(projectedEntityCount) | Nodes: \(projectedNodeCount)")
        lines.append("  Strategy: \(recommendedStrategy)")
        lines.append("  Priorities: accuracy=\(String(format: "%.0f", priorityWeights.accuracy * 100)) speed=\(String(format: "%.0f", priorityWeights.speed * 100)) completeness=\(String(format: "%.0f", priorityWeights.completeness * 100))")
        if !topIntents.isEmpty {
            lines.append("  Top intents:")
            for (i, intent) in topIntents.enumerated() {
                lines.append("    \(i + 1). \(intent.objective) (\(String(format: "%.0f", intent.confidence * 100))%)")
            }
        }
        return lines.joined(separator: "\n")
    }

    func toJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self),
              let json = String(data: data, encoding: .utf8) else { return "{}" }
        return json
    }
}

// MARK: — Array Safe Subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
