import Foundation

// MARK: - Unified Mirror Pipeline

/// Single entry point that wires all 9 intelligence layers together.
/// This is what the execution engine consumes and what the API exposes.
struct MirrorPipeline {

    // MARK: - Full Analysis Pipeline (events → complete intelligence output)

    static func analyze(
        sessionId: String,
        events: [EventTapManager.CapturedEvent],
        metadata: [String: Any] = [:]
    ) -> PipelineOutput {
        let startTime = Date()

        // Layer 1: Semantic Actions
        let semanticActions = SemanticActionExtractor.extract(from: events)

        // Layer 2: Workflow Intent
        let artifacts = WorkflowIntentExtractor.extractArtifacts(from: semanticActions, events: events)
        let intent = WorkflowIntentExtractor.inferIntent(actions: semanticActions, artifacts: artifacts)

        // Layer 3: Workflow Graph
        let graph = WorkflowGraphBuilder.buildFullGraph(from: semanticActions, artifacts: artifacts, intent: intent, events: events)

        // Layer 4: Entity Graph
        let entityGraph = EntityGraphBuilder.build(events: events, actions: semanticActions, artifacts: artifacts, graph: graph)

        // Layer 5: Editor Graph (migrated for UI)
        let editorGraph = EditorGraphMigrator.migrate(from: graph)

        // Layer 6: Belief State (continuously updated)
        var beliefState = BeliefStateEngine.initialize(sessionId: sessionId)
        BeliefStateEngine.update(&beliefState, events: events, partialActions: semanticActions, partialArtifacts: artifacts)

        // Layer 7: Evaluation
        let debugBundle = WorkflowEvaluationEngine.evaluateWorkflow(
            sessionId: sessionId, events: events, actions: semanticActions,
            intent: intent, graph: graph, entityGraph: entityGraph
        )

        // Layer 8: Policy Decision
        let context = OutcomePolicyEngine.extractContext(from: semanticActions, artifacts: artifacts, events: events)
        let hypotheses = HypothesisBuilder.buildHypotheses(from: semanticActions, intent: intent, artifacts: artifacts, graph: graph)
        let strategyTable = StrategyScoreTable(entries: [:], lastCompactionAt: Date(), totalEvaluations: 0, averageReward: 0)
        let hypothesisTable = HypothesisTable(distributions: [:], totalHypothesesTracked: 0, lastCompactionAt: Date())
        let policyDecision = OutcomePolicyEngine.decideStrategyAndHypothesis(
            context: context, hypotheses: hypotheses,
            strategyTable: strategyTable, hypothesisTable: hypothesisTable
        )

        // Layer 9: Belief State Snapshot
        let snapshot = BeliefStateEngine.snapshot(from: beliefState)

        let duration = Date().timeIntervalSince(startTime)

        return PipelineOutput(
            sessionId: sessionId,
            timestamp: Date(),
            pipelineDurationSeconds: duration,
            eventCount: events.count,
            semanticActions: semanticActions,
            intent: intent,
            artifacts: artifacts,
            workflowGraph: graph,
            entityGraph: entityGraph,
            editorGraphJSON: editorGraph.toReactFlowJSON(),
            beliefStateSnapshot: snapshot,
            policyDecision: policyDecision,
            debugBundle: debugBundle,
            metrics: PipelineMetrics(
                actionCount: semanticActions.count,
                artifactCount: artifacts.count,
                graphNodeCount: graph.nodes.count,
                graphEdgeCount: graph.edges.count,
                intentEntropy: beliefState.intentDistribution.entropy,
                overallConfidence: beliefState.metrics.overallEntropy
            )
        )
    }

    // MARK: - Incremental Update (per event batch)

    static func update(
        state: inout BeliefState,
        events: [EventTapManager.CapturedEvent],
        partialActions: [SemanticAction] = [],
        partialArtifacts: [ExtractedArtifact] = []
    ) -> BeliefStateSnapshot {
        BeliefStateEngine.update(&state, events: events, partialActions: partialActions, partialArtifacts: partialArtifacts)
        return BeliefStateEngine.snapshot(from: state)
    }

    // MARK: - Feedback Loop

    static func ingestFeedback(
        bundle: DebugBundle,
        state: inout BeliefState,
        strategyTable: inout StrategyScoreTable,
        hypothesisTable: inout HypothesisTable,
        stateMachine: inout LearningLoopState
    ) -> LearningLoopResult {
        let context = OutcomePolicyEngine.extractContext(from: bundle.groundTruth.semanticActions.map(\.output))
        let hypotheses = HypothesisBuilder.buildHypotheses(
            from: bundle.groundTruth.semanticActions.map(\.output),
            intent: bundle.groundTruth.workflowIntent.output
        )
        let strategy = OutcomePolicyEngine.selectStrategy(for: context, from: strategyTable)
        let (hypothesis, _, _) = HypothesisSelector.select(from: hypotheses, context: context, strategy: strategy, table: hypothesisTable)

        OutcomePolicyEngine.ingestFullFeedback(
            bundle: bundle, context: context, strategy: strategy,
            selectedHypothesis: hypothesis, strategyTable: &strategyTable, hypothesisTable: &hypothesisTable
        )

        BeliefStateEngine.update(
            &state, events: [],
            partialActions: bundle.groundTruth.semanticActions.map(\.output),
            partialArtifacts: WorkflowIntentExtractor.extractArtifacts(from: bundle.groundTruth.semanticActions.map(\.output), events: []),
            evaluation: bundle
        )

        return FailureToImprovementCompiler.executeLearningLoop(
            bundles: [bundle],
            calibrationRecords: bundle.calibrationRecords,
            state: &stateMachine
        )
    }
}

// MARK: - Pipeline Output

struct PipelineOutput: Codable {
    let sessionId: String
    let timestamp: Date
    let pipelineDurationSeconds: Double
    let eventCount: Int

    // Layer outputs
    let semanticActions: [SemanticAction]
    let intent: WorkflowIntent
    let artifacts: [ExtractedArtifact]
    let workflowGraph: WorkflowGraph
    let entityGraph: EntityGraph
    let editorGraphJSON: String
    let beliefStateSnapshot: BeliefStateSnapshot
    let policyDecision: PolicyDecision
    let debugBundle: DebugBundle

    // Summary metrics
    let metrics: PipelineMetrics

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

struct PipelineMetrics: Codable {
    let actionCount: Int
    let artifactCount: Int
    let graphNodeCount: Int
    let graphEdgeCount: Int
    let intentEntropy: Double
    let overallConfidence: Double
}
