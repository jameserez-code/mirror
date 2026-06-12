import Foundation

// MARK: ═══════════════════════════════════════════
// MARK: 1 — Ground Truth Record
// MARK: ═══════════════════════════════════════════

/// Complete snapshot of a workflow execution across all intelligence layers.
/// Used as the source of truth for evaluation, comparison, and calibration.
struct GroundTruthRecord: Codable, Identifiable {
    let id: String
    let sessionId: String
    let recordedAt: Date
    let evaluatedAt: Date

    // Raw capture
    let eventCount: Int
    let durationSeconds: Double

    // Layer 1: Semantic Actions
    let semanticActions: [LayerSnapshot<SemanticAction>]

    // Layer 2: Workflow Intent
    let workflowIntent: LayerSnapshot<WorkflowIntent>

    // Layer 3: Workflow Graph
    let workflowGraph: LayerSnapshot<WorkflowGraph>

    // Layer 4: Entity Graph
    let entityGraph: LayerSnapshot<EntityGraph>

    // Layer 5: Editor Graph
    let editorGraphJSON: String?   // serialized EditorGraph

    // Ground truth (user corrections or post-hoc evaluation)
    var userCorrections: [UserCorrection]
    var verifiedOutcome: VerifiedOutcome?

    struct UserCorrection: Codable, Identifiable {
        let id: String
        let timestamp: Date
        let targetLayer: LayerName
        let targetId: String           // nodeId, actionId, entityId
        let field: String              // which field was wrong
        let originalValue: String
        let correctedValue: String
        let reason: String?            // user's explanation
    }

    struct VerifiedOutcome: Codable {
        let success: Bool
        let expectedSteps: Int
        let completedSteps: Int
        let errorDescription: String?
        let userFeedback: String?
    }

    enum LayerName: String, Codable {
        case semantic
        case intent
        case graph
        case entity
        case editor
        case execution
    }
}

/// Generic wrapper that adds evaluation metadata to any layer output.
struct LayerSnapshot<T: Codable>: Codable {
    let output: T
    let generatedAt: Date
    let confidence: Double                 // self-reported confidence
    var evaluation: LayerEvaluation?       // post-hoc evaluation (populated later)
}

struct LayerEvaluation: Codable {
    var correctnessScore: Double           // 0.0-1.0
    var failureTypes: [FailureType]
    var calibrationDelta: Double           // predicted - actual
    var notes: String?
}

// MARK: ═══════════════════════════════════════════
// MARK: 2 — Failure Taxonomy
// MARK: ═══════════════════════════════════════════

enum FailureType: Codable, Hashable {
    // A. Perception Failure
    case missedEvents(count: Int)
    case incorrectGrouping(reason: String)
    case lostContextSignals(signals: [String])

    // B. Action Misclassification
    case wrongSemanticAction(expected: String, actual: String)
    case incorrectProviderDetection(detected: String, actual: String)
    case missedAction(actionType: String)

    // C. Intent Drift
    case wrongObjective(inferred: String, actual: String, delta: Double)
    case wrongDomain(detected: String, actual: String)
    case competingIntent(alternative: String, score: Double)

    // D. Graph Structure Error
    case incorrectNodeOrder(nodeIds: [String])
    case missingDependency(source: String, target: String)
    case wrongEdgeRelationship(edgeId: String, expected: String, actual: String)
    case orphanedNode(nodeId: String)

    // E. Entity Mapping Error
    case wrongFieldExtraction(field: String, extracted: String, actual: String)
    case incorrectColumnMapping(sourceColumn: String, targetColumn: String)
    case incorrectDocumentInterpretation(documentType: String, interpreted: String)
    case missedEntity(entityType: String)

    // F. Execution Mismatch
    case correctGraphWrongResult(nodeId: String, expected: String, actual: String)
    case executionTimeout(nodeId: String)
    case unexpectedExecutionError(nodeId: String, error: String)

    // Attachment targets
    var attachedNodeId: String? {
        switch self {
        case .wrongSemanticAction: return nil
        case .missedAction: return nil
        case .incorrectNodeOrder(let ids): return ids.first
        case .missingDependency(let source, _): return source
        case .wrongEdgeRelationship(let edgeId, _, _): return edgeId
        case .orphanedNode(let id): return id
        case .correctGraphWrongResult(let id, _, _): return id
        case .executionTimeout(let id): return id
        case .unexpectedExecutionError(let id, _): return id
        default: return nil
        }
    }

    var attachedEntityId: String? {
        switch self {
        case .wrongFieldExtraction: return nil
        case .incorrectColumnMapping: return nil
        case .incorrectDocumentInterpretation: return nil
        case .missedEntity: return nil
        default: return nil
        }
    }

    var category: FailureCategory {
        switch self {
        case .missedEvents, .incorrectGrouping, .lostContextSignals:
            return .perception
        case .wrongSemanticAction, .incorrectProviderDetection, .missedAction:
            return .actionMisclassification
        case .wrongObjective, .wrongDomain, .competingIntent:
            return .intentDrift
        case .incorrectNodeOrder, .missingDependency, .wrongEdgeRelationship, .orphanedNode:
            return .graphStructure
        case .wrongFieldExtraction, .incorrectColumnMapping, .incorrectDocumentInterpretation, .missedEntity:
            return .entityMapping
        case .correctGraphWrongResult, .executionTimeout, .unexpectedExecutionError:
            return .executionMismatch
        }
    }
}

enum FailureCategory: String, Codable, CaseIterable {
    case perception
    case actionMisclassification
    case intentDrift
    case graphStructure
    case entityMapping
    case executionMismatch
}

// MARK: ═══════════════════════════════════════════
// MARK: 3 — Confidence Calibration
// MARK: ═══════════════════════════════════════════

struct CalibrationRecord: Codable, Identifiable {
    let id: String
    let nodeType: String?              // e.g. "gmail_search", "extract_fields"
    let layer: String                  // "semantic", "intent", "graph", "entity"
    let predictedConfidence: Double
    let actualCorrectness: Double       // 0.0-1.0 from evaluation or user correction
    let calibrationDelta: Double        // predicted - actual
    let sessionId: String
    let timestamp: Date

    var calibrationQuality: CalibrationQuality {
        let absDelta = abs(calibrationDelta)
        if absDelta < 0.10 { return .wellCalibrated }
        if absDelta < 0.25 { return .moderatelyMiscalibrated }
        if calibrationDelta > 0 { return .overconfident }
        return .underconfident
    }
}

enum CalibrationQuality: String, Codable {
    case wellCalibrated          // |delta| < 0.10
    case moderatelyMiscalibrated // 0.10 <= |delta| < 0.25
    case overconfident           // delta > 0.25 (predicted too high)
    case underconfident          // delta < -0.25 (predicted too low)
}

/// Aggregated calibration stats per node type across all runs.
struct CalibrationSummary: Codable {
    let nodeType: String
    let sampleCount: Int
    let averagePredicted: Double
    let averageActual: Double
    let averageDelta: Double
    let quality: CalibrationQuality
    let trend: String             // "improving", "stable", "degrading"
}

// MARK: ═══════════════════════════════════════════
// MARK: 4 — Workflow Diff Engine
// MARK: ═══════════════════════════════════════════

struct WorkflowDiffReport: Codable {
    let sessionId: String
    let generatedAt: Date
    let aiGraphId: String
    let groundTruthId: String?

    var missingNodes: [DiffNode]          // in ground truth but not in AI graph
    var extraNodes: [DiffNode]            // in AI graph but not in ground truth
    var reorderedNodes: [Reordering]       // same node, different position
    var incorrectNodeTypes: [TypeMismatch] // same position, wrong type
    var incorrectEntityMappings: [MappingMismatch]
    var missingEdges: [DiffEdge]
    var extraEdges: [DiffEdge]

    var overallSimilarity: Double         // 0.0-1.0 Jaccard-like score

    struct DiffNode: Codable {
        let id: String
        let type: String
        let label: String
        let location: DiffLocation
    }

    struct Reordering: Codable {
        let nodeId: String
        let aiPosition: Int
        let actualPosition: Int
    }

    struct TypeMismatch: Codable {
        let nodeId: String
        let aiType: String
        let actualType: String
    }

    struct MappingMismatch: Codable {
        let entityId: String
        let field: String
        let aiMapping: String
        let actualMapping: String
    }

    struct DiffEdge: Codable {
        let id: String
        let source: String
        let target: String
        let type: String
    }

    enum DiffLocation: String, Codable {
        case aiOnly
        case groundTruthOnly
    }
}

// MARK: ═══════════════════════════════════════════
// MARK: 5 — Failure Replay System
// MARK: ═══════════════════════════════════════════

struct FailureReplay: Codable {
    let sessionId: String
    let workflowTitle: String
    let totalSteps: Int
    let divergencePoints: [DivergencePoint]
    let rootCauseAttribution: RootCauseAttribution
    let summary: String

    struct DivergencePoint: Codable {
        let stepIndex: Int
        let nodeId: String?
        let aiAction: String          // what the AI graph expected
        let actualBehavior: String    // what the user actually did
        let failureType: FailureType
        let likelySourceLayer: GroundTruthRecord.LayerName
        let explanation: String
    }
}

// MARK: ═══════════════════════════════════════════
// MARK: 6 — Instrumentation Hooks (Log Data)
// MARK: ═══════════════════════════════════════════

/// Data logged during extraction for later evaluation.
/// These are produced alongside the main pipeline, not instead of it.
struct InstrumentationLog: Codable {
    var semanticExtractor: SemanticInstrumentation?
    var intentExtractor: IntentInstrumentation?
    var graphBuilder: GraphInstrumentation?
    var entityBuilder: EntityInstrumentation?

    struct SemanticInstrumentation: Codable {
        var ambiguityScores: [String: Double]       // actionId → ambiguity
        var alternativeInterpretations: [String: [String]] // actionId → alt actions
        var eventCoverage: Double                    // % of events assigned to actions
        var unclassifiedEvents: Int
    }

    struct IntentInstrumentation: Codable {
        var top3Intents: [IntentCandidate]
        var reasoningFeatures: [String: Double]
        var templateMatchScore: Double
        var fallbackIntent: Bool

        struct IntentCandidate: Codable {
            let objective: String
            let score: Double
        }
    }

    struct GraphInstrumentation: Codable {
        var nodeSourceAttribution: [String: String]  // nodeId → actionId
        var edgeInferenceReason: [String: String]     // edgeId → "control_flow", "data_flow", "entity_link"
        var orphanedNodeIds: [String]
        var disconnectedComponentCount: Int
    }

    struct EntityInstrumentation: Codable {
        var fieldExtractionConfidence: [String: Double] // fieldId → confidence
        var mappingOrigin: [String: String]             // mappingId → "clipboard", "header", "inferred"
        var ambiguousMappings: [String: [String]]       // field → alt mappings
        var unmatchedFields: [String]                    // fields with no destination
    }
}

// MARK: ═══════════════════════════════════════════
// MARK: 7 — System-Wide Metrics
// MARK: ═══════════════════════════════════════════

struct SystemMetrics: Codable {
    let computedAt: Date
    let totalWorkflowsEvaluated: Int
    let totalSessionsRecorded: Int

    var actionAccuracy: Double
    var intentAccuracy: Double
    var graphStructuralAccuracy: Double
    var entityExtractionAccuracy: Double
    var endToEndSuccessRate: Double

    var byProvider: [String: ProviderMetrics]
    var byNodeType: [String: NodeTypeMetrics]
    var byArtifactType: [String: ArtifactMetrics]
    var calibrationByLayer: [String: CalibrationSummary]

    struct ProviderMetrics: Codable {
        let provider: String
        let actionAccuracy: Double
        let intentAccuracy: Double
        let workflowCount: Int
    }

    struct NodeTypeMetrics: Codable {
        let nodeType: String
        let occurrenceCount: Int
        let averageConfidence: Double
        let averageCorrectness: Double
        let failureRate: Double
    }

    struct ArtifactMetrics: Codable {
        let artifactType: String
        let extractionCount: Int
        let averageConfidence: Double
        let fieldAccuracy: Double
    }
}

// MARK: ═══════════════════════════════════════════
// MARK: 8 — Root Cause Attribution
// MARK: ═══════════════════════════════════════════

struct RootCauseAttribution: Codable {
    var perceptionProbability: Double
    var actionProbability: Double
    var intentProbability: Double
    var graphProbability: Double
    var entityProbability: Double
    var executionProbability: Double

    var primaryLayer: GroundTruthRecord.LayerName {
        let probs: [(GroundTruthRecord.LayerName, Double)] = [
            (.semantic, actionProbability),
            (.intent, intentProbability),
            (.graph, graphProbability),
            (.entity, entityProbability),
            (.execution, executionProbability),
        ]
        return probs.max(by: { $0.1 < $1.1 })?.0 ?? .semantic
    }

    var isModelConfusion: Bool {
        // High intent + entity probability → model misunderstood
        (intentProbability + entityProbability) > 0.5
    }

    var isMissingContext: Bool {
        // High perception + graph probability → missing signal
        (perceptionProbability + graphProbability) > 0.5
    }

    var recommendation: String {
        if isModelConfusion && isMissingContext {
            return "Compound failure: both model confusion and missing context. Prioritize improving extraction heuristics and providing richer event context to the AI."
        }
        if isModelConfusion {
            return "Model confusion detected. Improve AI prompt with more examples of this workflow type. Add clarifying context to the intent inference template."
        }
        if isMissingContext {
            return "Missing context signals. Enhance event capture to include additional metadata (page titles, OCR text, browser tab names). Increase frame sampling rate."
        }
        switch primaryLayer {
        case .semantic:
            return "Action extraction failure. Improve provider detection heuristics and event grouping logic."
        case .intent:
            return "Intent inference failure. Add more workflow templates or enrich the scoring function."
        case .graph:
            return "Graph structure failure. Improve edge inference and dependency detection."
        case .entity:
            return "Entity extraction failure. Improve field detection and mapping heuristics."
        case .execution:
            return "Execution failure. Check API connectivity, OAuth tokens, and step timeout configuration."
        default:
            return "Unclassified failure. Collect more ground truth data to improve diagnosis."
        }
    }
}

// MARK: ═══════════════════════════════════════════
// MARK: 9 — Debug Bundle
// MARK: ═══════════════════════════════════════════

struct DebugBundle: Codable {
    let sessionId: String
    let generatedAt: Date
    let workflowTitle: String

    var groundTruth: GroundTruthRecord
    var failureReport: FailureReport
    var diffReport: WorkflowDiffReport?
    var calibrationRecords: [CalibrationRecord]
    var rootCause: RootCauseAttribution
    var instrumentation: InstrumentationLog?
    var replay: FailureReplay?

    struct FailureReport: Codable {
        var totalFailures: Int
        var failuresByCategory: [FailureCategory: Int]
        var failuresByNodeId: [String: [FailureType]]
        var severityScore: Double       // 0.0-1.0; higher = more severe
    }

    func toJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }
}

// MARK: ═══════════════════════════════════════════
// MARK: Workflow Evaluation Engine
// MARK: ═══════════════════════════════════════════

struct WorkflowEvaluationEngine {

    // MARK: — Ground Truth Recording

    static func recordGroundTruth(
        sessionId: String,
        events: [EventTapManager.CapturedEvent],
        actions: [SemanticAction],
        intent: WorkflowIntent,
        graph: WorkflowGraph,
        entityGraph: EntityGraph,
        editorGraph: EditorGraph? = nil
    ) -> GroundTruthRecord {
        let now = Date()
        return GroundTruthRecord(
            id: "gt_\(sessionId)",
            sessionId: sessionId,
            recordedAt: now,
            evaluatedAt: now,
            eventCount: events.count,
            durationSeconds: (events.last?.timestamp ?? 0) - (events.first?.timestamp ?? 0),
            semanticActions: actions.map {
                LayerSnapshot(output: $0, generatedAt: now, confidence: $0.confidence, evaluation: nil)
            },
            workflowIntent: LayerSnapshot(output: intent, generatedAt: now, confidence: intent.confidence, evaluation: nil),
            workflowGraph: LayerSnapshot(output: graph, generatedAt: now, confidence: graph.confidence.overallConfidence, evaluation: nil),
            entityGraph: LayerSnapshot(output: entityGraph, generatedAt: now, confidence: entityGraph.confidence.overallConfidence, evaluation: nil),
            editorGraphJSON: editorGraph.flatMap { _ in EditorGraphMigrator.migrate(from: graph).toReactFlowJSON() },
            userCorrections: [],
            verifiedOutcome: nil
        )
    }

    // MARK: — Diff Engine

    static func diff(
        aiGraph: WorkflowGraph,
        groundTruthActions: [SemanticAction]
    ) -> WorkflowDiffReport {
        var report = WorkflowDiffReport(
            sessionId: aiGraph.id,
            generatedAt: Date(),
            aiGraphId: aiGraph.id,
            groundTruthId: nil,
            missingNodes: [], extraNodes: [], reorderedNodes: [], incorrectNodeTypes: [],
            incorrectEntityMappings: [], missingEdges: [], extraEdges: [],
            overallSimilarity: 0
        )

        let aiNodeIds = Set(aiGraph.nodes.map(\.id))
        let aiNodeTypes = Dictionary(uniqueKeysWithValues: aiGraph.nodes.map { ($0.id, $0.type.rawValue) })
        let aiNodeLabels = Dictionary(uniqueKeysWithValues: aiGraph.nodes.map { ($0.id, $0.label) })

        // Simulated ground truth: treat each semantic action as a node
        let gtNodeIds = Set(groundTruthActions.map(\.id))
        let gtNodeTypes = Dictionary(uniqueKeysWithValues: groundTruthActions.map { ($0.id, $0.action) })

        // Missing: in GT but not in AI
        let missing = gtNodeIds.subtracting(aiNodeIds)
        for id in missing {
            report.missingNodes.append(WorkflowDiffReport.DiffNode(
                id: id, type: gtNodeTypes[id] ?? "unknown",
                label: groundTruthActions.first(where: { $0.id == id })?.description ?? id,
                location: .groundTruthOnly
            ))
        }

        // Extra: in AI but not in GT
        let extra = aiNodeIds.subtracting(gtNodeIds)
        for id in extra {
            report.extraNodes.append(WorkflowDiffReport.DiffNode(
                id: id, type: aiNodeTypes[id] ?? "unknown",
                label: aiNodeLabels[id] ?? id,
                location: .aiOnly
            ))
        }

        // Type mismatches: same id, different type
        let common = aiNodeIds.intersection(gtNodeIds)
        for id in common {
            if let aiType = aiNodeTypes[id], let gtType = gtNodeTypes[id], aiType != gtType {
                report.incorrectNodeTypes.append(WorkflowDiffReport.TypeMismatch(
                    nodeId: id, aiType: aiType, actualType: gtType
                ))
            }
        }

        // Similarity: Jaccard on node IDs + type match bonus
        let unionSize = aiNodeIds.union(gtNodeIds).count
        let intersectionSize = aiNodeIds.intersection(gtNodeIds).count
        let typeMatches = common.filter { aiNodeTypes[$0] == gtNodeTypes[$0] }.count
        let baseScore = unionSize > 0 ? Double(intersectionSize) / Double(unionSize) : 0
        let typeScore = common.count > 0 ? Double(typeMatches) / Double(common.count) : 1.0
        report.overallSimilarity = baseScore * 0.4 + typeScore * 0.6

        return report
    }

    // MARK: — Failure Classification

    static func classifyFailures(
        aiGraph: WorkflowGraph,
        groundTruth: GroundTruthRecord,
        diffReport: WorkflowDiffReport
    ) -> [FailureType] {
        var failures: [FailureType] = []

        // From diff report → structural failures
        if !diffReport.missingNodes.isEmpty {
            failures.append(.missedAction(actionType: diffReport.missingNodes.map(\.type).joined(separator: ", ")))
        }
        for mismatch in diffReport.incorrectNodeTypes {
            failures.append(.wrongSemanticAction(expected: mismatch.actualType, actual: mismatch.aiType))
        }
        for node in diffReport.extraNodes {
            failures.append(.incorrectProviderDetection(detected: node.type, actual: "not_present"))
        }

        // Intent mismatch
        let gtIntent = groundTruth.workflowIntent.output
        let aiIntent = groundTruth.workflowIntent.output
        if gtIntent.objective != aiIntent.objective {
            failures.append(.wrongObjective(
                inferred: aiIntent.objective, actual: gtIntent.objective,
                delta: abs(aiIntent.confidence - gtIntent.confidence)
            ))
        }

        // Entity mapping failures (from field-level comparison)
        for correction in groundTruth.userCorrections where correction.targetLayer == .entity {
            failures.append(.wrongFieldExtraction(
                field: correction.field,
                extracted: correction.originalValue,
                actual: correction.correctedValue
            ))
        }

        return failures
    }

    // MARK: — Confidence Calibration

    static func calibrate(
        predictedConfidence: Double,
        actualCorrectness: Double,
        nodeType: String?,
        layer: String,
        sessionId: String
    ) -> CalibrationRecord {
        CalibrationRecord(
            id: "cal_\(UUID().uuidString.prefix(8))",
            nodeType: nodeType,
            layer: layer,
            predictedConfidence: predictedConfidence,
            actualCorrectness: actualCorrectness,
            calibrationDelta: predictedConfidence - actualCorrectness,
            sessionId: sessionId,
            timestamp: Date()
        )
    }

    static func calibrationSummary(for nodeType: String, records: [CalibrationRecord]) -> CalibrationSummary {
        let relevant = records.filter { $0.nodeType == nodeType }
        guard !relevant.isEmpty else {
            return CalibrationSummary(
                nodeType: nodeType, sampleCount: 0,
                averagePredicted: 0, averageActual: 0, averageDelta: 0,
                quality: .wellCalibrated, trend: "stable"
            )
        }
        let avgPred = relevant.map(\.predictedConfidence).reduce(0, +) / Double(relevant.count)
        let avgAct = relevant.map(\.actualCorrectness).reduce(0, +) / Double(relevant.count)
        let avgDelta = relevant.map(\.calibrationDelta).reduce(0, +) / Double(relevant.count)

        let quality: CalibrationQuality
        let absDelta = abs(avgDelta)
        if absDelta < 0.10 { quality = .wellCalibrated }
        else if absDelta < 0.25 { quality = .moderatelyMiscalibrated }
        else if avgDelta > 0 { quality = .overconfident }
        else { quality = .underconfident }

        // Trend: compare first half vs second half
        let mid = relevant.count / 2
        let trend: String
        if mid > 0 {
            let firstAvg = relevant[0..<mid].map(\.calibrationDelta).reduce(0, +) / Double(mid)
            let secondAvg = relevant[mid...].map(\.calibrationDelta).reduce(0, +) / Double(relevant.count - mid)
            if abs(secondAvg) < abs(firstAvg) * 0.8 { trend = "improving" }
            else if abs(secondAvg) > abs(firstAvg) * 1.2 { trend = "degrading" }
            else { trend = "stable" }
        } else {
            trend = "stable"
        }

        return CalibrationSummary(
            nodeType: nodeType, sampleCount: relevant.count,
            averagePredicted: avgPred, averageActual: avgAct, averageDelta: avgDelta,
            quality: quality, trend: trend
        )
    }

    // MARK: — Root Cause Attribution

    static func attributeRootCause(
        failures: [FailureType],
        diffReport: WorkflowDiffReport,
        calibrationRecords: [CalibrationRecord]
    ) -> RootCauseAttribution {
        guard !failures.isEmpty else {
            return RootCauseAttribution(
                perceptionProbability: 0, actionProbability: 0, intentProbability: 0,
                graphProbability: 0, entityProbability: 0, executionProbability: 0
            )
        }

        var counts: [FailureCategory: Int] = [:]
        for failure in failures { counts[failure.category, default: 0] += 1 }
        let total = Double(failures.count)

        // Base probabilities from failure counts
        var perception = Double(counts[.perception] ?? 0) / total
        var action = Double(counts[.actionMisclassification] ?? 0) / total
        var intent = Double(counts[.intentDrift] ?? 0) / total
        var graph = Double(counts[.graphStructure] ?? 0) / total
        var entity = Double(counts[.entityMapping] ?? 0) / total
        var execution = Double(counts[.executionMismatch] ?? 0) / total

        // Boost based on calibration quality
        let overconfidentNodes = calibrationRecords.filter { $0.calibrationQuality == .overconfident }
        if !overconfidentNodes.isEmpty {
            intent += 0.10  // overconfidence often means intent/model error
            entity += 0.05
        }

        // Graph structural issues amplify graph probability
        if diffReport.overallSimilarity < 0.5 {
            graph += 0.15
        }

        // Normalize
        let sum = perception + action + intent + graph + entity + execution
        if sum > 0 {
            perception /= sum
            action /= sum
            intent /= sum
            graph /= sum
            entity /= sum
            execution /= sum
        }

        return RootCauseAttribution(
            perceptionProbability: perception,
            actionProbability: action,
            intentProbability: intent,
            graphProbability: graph,
            entityProbability: entity,
            executionProbability: execution
        )
    }

    // MARK: — Failure Replay

    static func buildReplay(
        groundTruth: GroundTruthRecord,
        failures: [FailureType],
        rootCause: RootCauseAttribution
    ) -> FailureReplay {
        var divergencePoints: [FailureReplay.DivergencePoint] = []

        for (index, snapshot) in groundTruth.semanticActions.enumerated() {
            let action = snapshot.output
            let relevantFailures = failures.filter { f in
                f.attachedNodeId == action.id || f.attachedEntityId == action.id
            }

            for failure in relevantFailures {
                var aiAction = action.action
                var actual = action.description
                var sourceLayer: GroundTruthRecord.LayerName = .semantic

                switch failure {
                case .wrongSemanticAction(let expected, let actual_):
                    aiAction = actual_
                    actual = expected
                    sourceLayer = .semantic
                case .wrongObjective(let inferred, let actual_, _):
                    aiAction = inferred
                    actual = actual_
                    sourceLayer = .intent
                case .missingDependency:
                    aiAction = action.action
                    actual = "Missing upstream dependency"
                    sourceLayer = .graph
                case .wrongFieldExtraction(let field, let extracted, let actual_):
                    aiAction = extracted
                    actual = "\(field): \(actual_)"
                    sourceLayer = .entity
                default:
                    sourceLayer = rootCause.primaryLayer
                }

                divergencePoints.append(FailureReplay.DivergencePoint(
                    stepIndex: index,
                    nodeId: action.id,
                    aiAction: aiAction,
                    actualBehavior: actual,
                    failureType: failure,
                    likelySourceLayer: sourceLayer,
                    explanation: describeDivergence(failure: failure, sourceLayer: sourceLayer)
                ))
            }
        }

        return FailureReplay(
            sessionId: groundTruth.sessionId,
            workflowTitle: groundTruth.workflowGraph.output.title,
            totalSteps: groundTruth.semanticActions.count,
            divergencePoints: divergencePoints,
            rootCauseAttribution: rootCause,
            summary: buildReplaySummary(divergencePoints: divergencePoints, rootCause: rootCause)
        )
    }

    private static func describeDivergence(failure: FailureType, sourceLayer: GroundTruthRecord.LayerName) -> String {
        switch failure {
        case .wrongSemanticAction(let expected, let actual):
            return "Action misclassification: AI detected '\(actual)' but user performed '\(expected)'"
        case .missedAction(let type):
            return "Missed action: user performed '\(type)' but AI did not detect it"
        case .wrongObjective(let inferred, let actual, _):
            return "Intent mismatch: AI inferred '\(inferred)' but actual objective was '\(actual)'"
        case .missingDependency(let source, let target):
            return "Missing dependency: node '\(source)' should feed into '\(target)'"
        case .wrongFieldExtraction(let field, let extracted, let actual):
            return "Field error: extracted '\(field)' as '\(extracted)' but should be '\(actual)'"
        case .incorrectProviderDetection(let detected, let actual):
            return "Provider error: detected '\(detected)' but actual app is '\(actual)'"
        default:
            return "Divergence in \(sourceLayer.rawValue) layer"
        }
    }

    private static func buildReplaySummary(divergencePoints: [FailureReplay.DivergencePoint], rootCause: RootCauseAttribution) -> String {
        guard !divergencePoints.isEmpty else { return "No divergences detected." }

        let primary = rootCause.primaryLayer.rawValue
        let conf = rootCause.isModelConfusion ? "model confusion" : "missing context"
        return "\(divergencePoints.count) divergence(s) detected. Primary failure source: \(primary) (\(conf)). \(rootCause.recommendation)"
    }

    // MARK: — System Metrics

    static func computeMetrics(
        groundTruths: [GroundTruthRecord],
        calibrationRecords: [CalibrationRecord] = []
    ) -> SystemMetrics {
        var metrics = SystemMetrics(
            computedAt: Date(),
            totalWorkflowsEvaluated: groundTruths.count,
            totalSessionsRecorded: groundTruths.count,
            actionAccuracy: 0, intentAccuracy: 0, graphStructuralAccuracy: 0,
            entityExtractionAccuracy: 0, endToEndSuccessRate: 0,
            byProvider: [:], byNodeType: [:], byArtifactType: [:],
            calibrationByLayer: [:]
        )

        guard !groundTruths.isEmpty else { return metrics }

        // Action accuracy: % of actions whose types match ground truth
        var actionCorrect = 0, actionTotal = 0
        var intentCorrect = 0
        var graphScores: [Double] = []
        var entityScores: [Double] = []
        var e2eSuccess = 0

        var providerStats: [String: (correct: Int, total: Int, intents: Int)] = [:]
        var nodeTypeStats: [String: (count: Int, confidence: Double, failures: Int)] = [:]

        for gt in groundTruths {
            for snapshot in gt.semanticActions {
                actionTotal += 1
                let provider = snapshot.output.provider
                nodeTypeStats[snapshot.output.action, default: (0, 0, 0)].count += 1

                if let eval = snapshot.evaluation {
                    if eval.correctnessScore > 0.8 { actionCorrect += 1 }
                    nodeTypeStats[snapshot.output.action]!.confidence += snapshot.confidence
                    if eval.correctnessScore < 0.5 { nodeTypeStats[snapshot.output.action]!.failures += 1 }
                }
                providerStats[provider, default: (0, 0, 0)].total += 1
            }

            if let eval = gt.workflowIntent.evaluation {
                if eval.correctnessScore > 0.8 { intentCorrect += 1 }
            }

            if let eval = gt.workflowGraph.evaluation {
                graphScores.append(eval.correctnessScore)
            }
            if let eval = gt.entityGraph.evaluation {
                entityScores.append(eval.correctnessScore)
            }
            if gt.verifiedOutcome?.success == true { e2eSuccess += 1 }
        }

        metrics.actionAccuracy = actionTotal > 0 ? Double(actionCorrect) / Double(actionTotal) : 0
        metrics.intentAccuracy = groundTruths.count > 0 ? Double(intentCorrect) / Double(groundTruths.count) : 0
        metrics.graphStructuralAccuracy = graphScores.isEmpty ? 0 : graphScores.reduce(0, +) / Double(graphScores.count)
        metrics.entityExtractionAccuracy = entityScores.isEmpty ? 0 : entityScores.reduce(0, +) / Double(entityScores.count)
        metrics.endToEndSuccessRate = groundTruths.count > 0 ? Double(e2eSuccess) / Double(groundTruths.count) : 0

        // Provider metrics
        for (provider, stats) in providerStats {
            metrics.byProvider[provider] = SystemMetrics.ProviderMetrics(
                provider: provider,
                actionAccuracy: stats.total > 0 ? Double(stats.correct) / Double(stats.total) : 0,
                intentAccuracy: stats.intents > 0 ? 0.5 : 0,
                workflowCount: stats.total
            )
        }

        // Node type metrics
        for (type, stats) in nodeTypeStats {
            metrics.byNodeType[type] = SystemMetrics.NodeTypeMetrics(
                nodeType: type,
                occurrenceCount: stats.count,
                averageConfidence: stats.count > 0 ? stats.confidence / Double(stats.count) : 0,
                averageCorrectness: 0.5, // placeholder
                failureRate: stats.count > 0 ? Double(stats.failures) / Double(stats.count) : 0
            )
        }

        return metrics
    }

    // MARK: — Debug Bundle Assembly

    static func assembleDebugBundle(
        groundTruth: GroundTruthRecord,
        diffReport: WorkflowDiffReport? = nil,
        failures: [FailureType] = [],
        calibrationRecords: [CalibrationRecord] = [],
        instrumentation: InstrumentationLog? = nil
    ) -> DebugBundle {
        let rootCause = attributeRootCause(failures: failures, diffReport: diffReport ?? WorkflowDiffReport(
            sessionId: groundTruth.sessionId, generatedAt: Date(), aiGraphId: groundTruth.id, groundTruthId: nil,
            missingNodes: [], extraNodes: [], reorderedNodes: [], incorrectNodeTypes: [],
            incorrectEntityMappings: [], missingEdges: [], extraEdges: [], overallSimilarity: 1.0
        ), calibrationRecords: calibrationRecords)

        let replay = buildReplay(groundTruth: groundTruth, failures: failures, rootCause: rootCause)

        var failureByCategory: [FailureCategory: Int] = [:]
        var failureByNode: [String: [FailureType]] = [:]
        for f in failures {
            failureByCategory[f.category, default: 0] += 1
            if let nodeId = f.attachedNodeId {
                failureByNode[nodeId, default: []].append(f)
            }
        }

        let severityScore = failures.isEmpty ? 0 : min(Double(failures.count) / Double(max(groundTruth.semanticActions.count, 1)), 1.0)

        return DebugBundle(
            sessionId: groundTruth.sessionId,
            generatedAt: Date(),
            workflowTitle: groundTruth.workflowGraph.output.title,
            groundTruth: groundTruth,
            failureReport: DebugBundle.FailureReport(
                totalFailures: failures.count,
                failuresByCategory: failureByCategory,
                failuresByNodeId: failureByNode,
                severityScore: severityScore
            ),
            diffReport: diffReport,
            calibrationRecords: calibrationRecords,
            rootCause: rootCause,
            instrumentation: instrumentation,
            replay: replay
        )
    }

    // MARK: — Convenience: Full Evaluation Pipeline

    static func evaluateWorkflow(
        sessionId: String,
        events: [EventTapManager.CapturedEvent],
        actions: [SemanticAction],
        intent: WorkflowIntent,
        graph: WorkflowGraph,
        entityGraph: EntityGraph,
        userCorrections: [GroundTruthRecord.UserCorrection] = [],
        verifiedOutcome: GroundTruthRecord.VerifiedOutcome? = nil
    ) -> DebugBundle {
        var gt = recordGroundTruth(
            sessionId: sessionId, events: events, actions: actions,
            intent: intent, graph: graph, entityGraph: entityGraph
        )
        gt.userCorrections = userCorrections
        gt.verifiedOutcome = verifiedOutcome

        let diff = diff(aiGraph: graph, groundTruthActions: actions)
        let failures = classifyFailures(aiGraph: graph, groundTruth: gt, diffReport: diff)

        var calibrationRecords: [CalibrationRecord] = []
        for snapshot in gt.semanticActions {
            if let eval = snapshot.evaluation {
                calibrationRecords.append(calibrate(
                    predictedConfidence: snapshot.confidence,
                    actualCorrectness: eval.correctnessScore,
                    nodeType: snapshot.output.action,
                    layer: "semantic",
                    sessionId: sessionId
                ))
            }
        }

        return assembleDebugBundle(
            groundTruth: gt, diffReport: diff, failures: failures,
            calibrationRecords: calibrationRecords
        )
    }

    // MARK: — System Metrics from History

    static func computeSystemMetrics(from debugBundles: [DebugBundle]) -> SystemMetrics {
        let groundTruths = debugBundles.map(\.groundTruth)
        let calibrationRecords = debugBundles.flatMap(\.calibrationRecords)
        return computeMetrics(groundTruths: groundTruths, calibrationRecords: calibrationRecords)
    }
}
