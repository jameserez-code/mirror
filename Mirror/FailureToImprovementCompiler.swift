import Foundation

// MARK: ═══════════════════════════════════════════
// MARK: 1 — Failure Pattern Mining
// MARK: ═══════════════════════════════════════════

struct FailurePattern: Codable, Identifiable {
    let id: String
    var name: String
    var description: String
    var frequency: Int                          // number of occurrences
    var affectedNodeTypes: [String]
    var affectedProviders: [String]
    var failureCategoryDistribution: [FailureCategory: Double]
    var rootCauseDistribution: [GroundTruthRecord.LayerName: Double]
    var averageSeverity: Double
    var representativeSessionIds: [String]
    var firstSeenAt: Date
    var lastSeenAt: Date

    var isRecurring: Bool { frequency >= 3 }
    var isHighSeverity: Bool { averageSeverity > 0.6 }
    var primaryAffectedLayer: GroundTruthRecord.LayerName {
        rootCauseDistribution.max(by: { $0.value < $1.value })?.key ?? .semantic
    }
}

struct PatternCluster: Codable {
    let clusterId: String
    var patterns: [FailurePattern]
    var centroid: ClusterCentroid
    var intraClusterDistance: Double           // how tight is the cluster?

    struct ClusterCentroid: Codable {
        var dominantNodeTypes: [String]
        var dominantFailures: [FailureCategory]
        var dominantLayer: GroundTruthRecord.LayerName
        var averageConfidence: Double
    }
}

// MARK: ═══════════════════════════════════════════
// MARK: 2 — Failure Signature
// MARK: ═══════════════════════════════════════════

struct FailureSignature: Codable, Identifiable {
    let id: String
    let patternId: String
    var name: String
    var triggerConditions: [TriggerCondition]
    var affectedComponents: [String]            // node types, providers, actions
    var likelihoodScore: Double                 // probability this signature fires
    var detectionRules: [DetectionRule]
    var severity: Double
    var createdAt: Date
    var updatedAt: Date

    struct TriggerCondition: Codable {
        let field: String                       // "nodeTypes", "provider", "actionSequence", "entityConfidence"
        let operator_: ConditionOperator
        let value: String

        enum ConditionOperator: String, Codable {
            case contains, equals, lessThan, greaterThan, inSet, matches
        }

        func evaluate(context: SignatureContext) -> Bool {
            switch field {
            case "nodeTypes":
                let types = context.nodeTypes.joined(separator: ",")
                return evaluateString(types, against: value)
            case "provider":
                return evaluateString(context.primaryProvider, against: value)
            case "actionSequence":
                let seq = context.actionSequence.joined(separator: ",")
                return evaluateString(seq, against: value)
            case "entityConfidence":
                guard let conf = context.entityConfidence else { return false }
                return evaluateNumeric(conf, against: Double(value) ?? 0)
            case "actionCount":
                return evaluateNumeric(Double(context.actionCount), against: Double(value) ?? 0)
            default:
                return false
            }
        }

        private func evaluateString(_ s: String, against v: String) -> Bool {
            switch operator_ {
            case .contains: return s.contains(v)
            case .equals: return s == v
            case .inSet: return v.split(separator: ",").map(String.init).contains(s)
            case .matches: return s.range(of: v, options: .regularExpression) != nil
            default: return false
            }
        }

        private func evaluateNumeric(_ n: Double, against v: Double) -> Bool {
            switch operator_ {
            case .lessThan: return n < v
            case .greaterThan: return n > v
            case .equals: return n == v
            default: return false
            }
        }
    }

    struct DetectionRule: Codable {
        let ruleId: String
        let description: String
        let condition: TriggerCondition
    }
}

struct SignatureContext: Codable {
    var nodeTypes: [String]
    var actionSequence: [String]
    var primaryProvider: String
    var entityConfidence: Double?
    var actionCount: Int
    var sessionId: String
}

// MARK: ═══════════════════════════════════════════
// MARK: 3 — Inference Adjustments
// MARK: ═══════════════════════════════════════════

struct InferenceAdjustments: Codable {
    var semanticAdjustments: SemanticAdjustments
    var intentAdjustments: IntentAdjustments
    var graphAdjustments: GraphAdjustments
    var entityAdjustments: EntityAdjustments
    var calibrationAdjustments: CalibrationAdjustments

    struct SemanticAdjustments: Codable {
        var heuristicWeights: [String: Double]          // actionType → weight modifier
        var providerDetectionOverrides: [String: String] // detected → actual
        var ambiguityResolutionRules: [AmbiguityRule]
        var groupingGapThreshold: Double?                // override maxIdleGap

        struct AmbiguityRule: Codable {
            let id: String
            let condition: String                       // e.g. "typedText contains invoice"
            let preferAction: String                     // e.g. "gmail_search"
            let overAction: String                       // e.g. "type_text"
            let confidenceBoost: Double
        }
    }

    struct IntentAdjustments: Codable {
        var templateWeights: [String: Double]            // templateObjective → weight
        var keywordExpansions: [String: [String]]        // objective → additional keywords
        var intentRankingOverrides: [String: Int]        // objective → rank
        var minimumTemplateScore: Double?
    }

    struct GraphAdjustments: Codable {
        var edgeInferenceWeights: [String: Double]       // edgeType → weight
        var nodeOrderingRules: [OrderingRule]
        var dataFlowPrioritization: [String: Double]     // provider → priority

        struct OrderingRule: Codable {
            let id: String
            let before: String
            let after: String
            let reason: String
        }
    }

    struct EntityAdjustments: Codable {
        var fieldExtractionCorrections: [String: String]  // fieldName → correctedFieldName
        var mappingConfidenceOffsets: [String: Double]    // mappingType → offset
        var entityMergeRules: [EntityMergeRule]
        var headerMatchingBias: Double?                   // bias toward header similarity

        struct EntityMergeRule: Codable {
            let id: String
            let entityTypeA: String
            let entityTypeB: String
            let mergeInto: String
            let whenCondition: String?
        }
    }

    struct CalibrationAdjustments: Codable {
        var scaleFactors: [String: Double]               // nodeType → confidence multiplier
        var offsets: [String: Double]                     // nodeType → additive offset
        var providerOffsets: [String: Double]             // provider → additive offset
        var recalibrationCurves: [String: [Double]]       // nodeType → [calibratedValues]
    }
}

// MARK: ═══════════════════════════════════════════
// MARK: 4 — Improvement Patch
// MARK: ═══════════════════════════════════════════

struct ImprovementPatch: Codable, Identifiable {
    let id: String
    let version: Int
    let name: String
    let description: String
    let createdAt: Date
    var appliedAt: Date?
    var status: PatchStatus

    let affectedLayer: AffectedLayer
    let changeType: ChangeType
    let adjustments: InferenceAdjustments
    var rules: [SynthesizedRule]

    let expectedImpact: ImpactEstimate
    let regressionRisk: RegressionAssessment
    let rollbackKey: String
    var isActive: Bool

    enum AffectedLayer: String, Codable {
        case semantic
        case intent
        case graph
        case entity
        case calibration
        case multi
    }

    enum ChangeType: String, Codable {
        case weightAdjustment
        case ruleAddition
        case calibrationShift
        case heuristicTweak
        case templateUpdate
        case combined
    }

    enum PatchStatus: String, Codable {
        case proposed
        case simulated
        case approved
        case applied
        case rolledBack
        case superseded
    }

    struct ImpactEstimate: Codable {
        var expectedAccuracyGain: Double         // 0.0-1.0
        var affectedWorkflowCount: Int
        var confidenceDeltaShift: Double         // positive = improved calibration
        var nodeTypesImproved: [String]
        var estimatedFalsePositiveReduction: Double
    }

    struct RegressionAssessment: Codable {
        var regressionRisk: Double               // 0.0-1.0; lower is better
        var workflowsAtRisk: Int
        var potentiallyDegradedAreas: [String]   // node types or providers
        var isSafe: Bool { regressionRisk < 0.15 }
    }
}

// MARK: ═══════════════════════════════════════════
// MARK: 5 — Synthesized Rules
// MARK: ═══════════════════════════════════════════

struct SynthesizedRule: Codable, Identifiable {
    let id: String
    let version: Int
    let description: String                 // human-readable
    let condition: RuleCondition
    let action: RuleAction
    let confidence: Double
    let evidenceCount: Int                  // how many failures support this rule
    let createdAt: Date
    let isReversible: Bool
    let rollbackRuleId: String?

    struct RuleCondition: Codable {
        let field: String
        let operator_: FailureSignature.TriggerCondition.ConditionOperator
        let value: String
    }

    struct RuleAction: Codable {
        let target: String                  // "entityMappingConfidence", "nodeOrder:gmail_search", etc.
        let operation: ActionOperation
        let value: Double
        let layer: ImprovementPatch.AffectedLayer
    }

    enum ActionOperation: String, Codable {
        case multiply          // scale by value
        case add               // add value
        case setTo             // set to exact value
        case clamp             // clamp to [0, value]
        case boostIf           // boost if condition matches
        case penalizeIf        // penalize if condition matches
        case prioritize        // move earlier in ordering
        case deprioritize       // move later in ordering
    }
}

// MARK: ═══════════════════════════════════════════
// MARK: 6 — Patch Simulator
// MARK: ═══════════════════════════════════════════

struct SimulationResult: Codable {
    let patchId: String
    let simulatedAt: Date
    let testedOnDebugBundles: Int

    var accuracyGain: Double                // average improvement
    var regressionCount: Int                // workflows that got worse
    var regressionSeverity: Double          // how much worse
    var netGain: Double                      // accuracyGain - regressionSeverity * 0.5
    var affectedWorkflowIds: [String]
    var confidenceShiftPerNode: [String: Double] // nodeType → delta

    var isNetPositive: Bool { netGain > 0 }
    var isSafe: Bool { regressionCount <= 1 && netGain > 0.02 }
    var recommendation: PatchRecommendation

    enum PatchRecommendation: String, Codable {
        case deploy
        case deployWithCaution
        case revise
        case reject
    }
}

// MARK: ═══════════════════════════════════════════
// MARK: 7 — Continuous Learning Loop
// MARK: ═══════════════════════════════════════════

struct LearningLoopState: Codable {
    var totalWorkflowsProcessed: Int
    var totalPatchesGenerated: Int
    var totalPatchesApplied: Int
    var activePatches: [String]                  // patch IDs
    var currentAccuracyTrend: String             // "improving", "stable", "degrading"
    var lastLoopAt: Date?
    var loopCount: Int
    var accumulatedGain: Double                  // total accuracy improvement from patches

    var deploymentThresholds: DeploymentThresholds

    struct DeploymentThresholds: Codable {
        var minImprovementConfidence: Double = 0.65
        var maxRegressionRisk: Double = 0.15
        var minSupportingPatterns: Int = 3
    }
}

// MARK: ═══════════════════════════════════════════
// MARK: Failure-to-Improvement Compiler
// MARK: ═══════════════════════════════════════════

struct FailureToImprovementCompiler {

    // MARK: — 1. Pattern Mining

    static func minePatterns(from bundles: [DebugBundle]) -> [FailurePattern] {
        var patterns: [FailurePattern] = []
        var patternId = 0

        // Group bundles by dominant failure category + affected node types
        var grouped: [String: [DebugBundle]] = [:]
        for bundle in bundles {
            let key = clusteringKey(for: bundle)
            grouped[key, default: []].append(bundle)
        }

        for (_, group) in grouped where group.count >= 2 {
            patternId += 1
            patterns.append(buildPattern(id: "pattern\(patternId)", from: group))
        }

        // Sort by frequency (most common first)
        return patterns.sorted { $0.frequency > $1.frequency }
    }

    private static func clusteringKey(for bundle: DebugBundle) -> String {
        let categories = bundle.failureReport.failuresByCategory.keys
            .sorted(by: { $0.rawValue < $1.rawValue })
            .map(\.rawValue)
            .joined(separator: "+")
        let nodes = bundle.groundTruth.semanticActions.map(\.output.action)
            .reduce(into: Set<String>()) { $0.insert($1) }
            .sorted()
            .prefix(3)
            .joined(separator: ",")
        return "\(categories)|\(nodes)"
    }

    private static func buildPattern(id: String, from bundles: [DebugBundle]) -> FailurePattern {
        var nodeTypeSet: Set<String> = []
        var providerSet: Set<String> = []
        var catDist: [FailureCategory: Double] = [:]
        var rootDist: [GroundTruthRecord.LayerName: Double] = [:]
        var totalFailures = 0

        for bundle in bundles {
            for action in bundle.groundTruth.semanticActions {
                nodeTypeSet.insert(action.output.action)
                providerSet.insert(action.output.provider)
            }
            for (cat, count) in bundle.failureReport.failuresByCategory {
                catDist[cat, default: 0] += Double(count)
                totalFailures += count
            }
            let rc = bundle.rootCause
            rootDist[.semantic, default: 0] += rc.actionProbability
            rootDist[.intent, default: 0] += rc.intentProbability
            rootDist[.graph, default: 0] += rc.graphProbability
            rootDist[.entity, default: 0] += rc.entityProbability
            rootDist[.execution, default: 0] += rc.executionProbability
        }

        // Normalize
        if totalFailures > 0 {
            for key in catDist.keys { catDist[key]! /= Double(bundles.count) }
        }
        for key in rootDist.keys { rootDist[key]! /= Double(bundles.count) }

        let primaryCat = catDist.max(by: { $0.value < $1.value })?.key ?? .actionMisclassification
        let sev = bundles.map(\.failureReport.severityScore).reduce(0, +) / Double(bundles.count)

        return FailurePattern(
            id: id,
            name: "\(primaryCat.rawValue) in \(nodeTypeSet.sorted().prefix(2).joined(separator: ", "))",
            description: "Recurring \(primaryCat.rawValue) failures affecting \(nodeTypeSet.count) node types across \(providerSet.count) providers",
            frequency: bundles.count,
            affectedNodeTypes: Array(nodeTypeSet),
            affectedProviders: Array(providerSet),
            failureCategoryDistribution: catDist,
            rootCauseDistribution: rootDist,
            averageSeverity: sev,
            representativeSessionIds: bundles.map(\.sessionId),
            firstSeenAt: bundles.map(\.groundTruth.recordedAt).min() ?? Date(),
            lastSeenAt: bundles.map(\.groundTruth.recordedAt).max() ?? Date()
        )
    }

    // MARK: — 2. Failure Signature Generation

    static func generateSignatures(from patterns: [FailurePattern], bundles: [DebugBundle]) -> [FailureSignature] {
        var signatures: [FailureSignature] = []

        for pattern in patterns where pattern.frequency >= 2 {
            _ = extractSignatureContext(from: pattern, bundles: bundles)
            var triggers: [FailureSignature.TriggerCondition] = []

            // Node type trigger
            if !pattern.affectedNodeTypes.isEmpty {
                let types = pattern.affectedNodeTypes.joined(separator: ",")
                triggers.append(.init(field: "nodeTypes", operator_: .contains, value: types))
            }

            // Entity confidence trigger
            if pattern.primaryAffectedLayer == .entity {
                triggers.append(.init(field: "entityConfidence", operator_: .lessThan, value: "0.7"))
            }

            // Action count trigger
            triggers.append(.init(field: "actionCount", operator_: .greaterThan, value: "2"))

            // Detection rules
            var rules: [FailureSignature.DetectionRule] = []
            for cond in triggers {
                rules.append(.init(ruleId: "dr_\(UUID().uuidString.prefix(8))", description: "Trigger when \(cond.field) \(cond.operator_.rawValue) \(cond.value)", condition: cond))
            }

            signatures.append(FailureSignature(
                id: "sig_\(pattern.id)",
                patternId: pattern.id,
                name: "Signature: \(pattern.name)",
                triggerConditions: triggers,
                affectedComponents: pattern.affectedNodeTypes,
                likelihoodScore: Double(pattern.frequency) / Double(max(bundles.count, 1)),
                detectionRules: rules,
                severity: pattern.averageSeverity,
                createdAt: Date(),
                updatedAt: Date()
            ))
        }

        return signatures
    }

    private static func extractSignatureContext(from pattern: FailurePattern, bundles: [DebugBundle]) -> SignatureContext {
        let relevantBundles = bundles.filter { pattern.representativeSessionIds.contains($0.sessionId) }
        return SignatureContext(
            nodeTypes: pattern.affectedNodeTypes,
            actionSequence: relevantBundles.first?.groundTruth.semanticActions.map(\.output.action) ?? [],
            primaryProvider: pattern.affectedProviders.first ?? "unknown",
            entityConfidence: pattern.primaryAffectedLayer == .entity ? 0.5 : nil,
            actionCount: relevantBundles.first?.groundTruth.semanticActions.count ?? 0,
            sessionId: pattern.representativeSessionIds.first ?? ""
        )
    }

    // MARK: — 3. Inference Adjustment Generation

    static func generateAdjustments(from patterns: [FailurePattern], signatures: [FailureSignature], calibrationRecords: [CalibrationRecord]) -> InferenceAdjustments {
        var semantic = InferenceAdjustments.SemanticAdjustments(
            heuristicWeights: [:], providerDetectionOverrides: [:], ambiguityResolutionRules: [], groupingGapThreshold: nil
        )
        var intent = InferenceAdjustments.IntentAdjustments(
            templateWeights: [:], keywordExpansions: [:], intentRankingOverrides: [:], minimumTemplateScore: nil
        )
        var graph = InferenceAdjustments.GraphAdjustments(
            edgeInferenceWeights: [:], nodeOrderingRules: [], dataFlowPrioritization: [:]
        )
        var entity = InferenceAdjustments.EntityAdjustments(
            fieldExtractionCorrections: [:], mappingConfidenceOffsets: [:], entityMergeRules: [], headerMatchingBias: nil
        )
        var calibration = InferenceAdjustments.CalibrationAdjustments(
            scaleFactors: [:], offsets: [:], providerOffsets: [:], recalibrationCurves: [:]
        )

        for pattern in patterns {
            switch pattern.primaryAffectedLayer {
            case .semantic:
                for nodeType in pattern.affectedNodeTypes {
                    semantic.heuristicWeights[nodeType] = max((semantic.heuristicWeights[nodeType] ?? 0.95), 0.85)
                }
                // Add ambiguity resolution for common confusion pairs
                if pattern.affectedNodeTypes.contains("gmail_search") && pattern.affectedNodeTypes.contains("type_text") {
                    semantic.ambiguityResolutionRules.append(.init(
                        id: "ar_\(pattern.id)",
                        condition: "typedText contains @ or mail.google.com",
                        preferAction: "gmail_search",
                        overAction: "type_text",
                        confidenceBoost: 0.10
                    ))
                }

            case .intent:
                for nodeType in pattern.affectedNodeTypes {
                    intent.templateWeights[nodeType] = 0.9
                }

            case .graph:
                for nodeType in pattern.affectedNodeTypes {
                    graph.edgeInferenceWeights[nodeType] = 0.85
                }

            case .entity:
                for nodeType in pattern.affectedNodeTypes {
                    entity.mappingConfidenceOffsets[nodeType] = -0.05
                }
                entity.headerMatchingBias = 0.15

            case .execution:
                for nodeType in pattern.affectedNodeTypes {
                    calibration.offsets[nodeType] = -0.10
                }

            default: break
            }
        }

        // Calibration from records
        for record in calibrationRecords where record.calibrationQuality == .overconfident {
            if let nodeType = record.nodeType {
                calibration.scaleFactors[nodeType] = 0.88  // reduce by ~12%
            }
        }
        for record in calibrationRecords where record.calibrationQuality == .underconfident {
            if let nodeType = record.nodeType {
                calibration.offsets[nodeType] = (calibration.offsets[nodeType] ?? 0) + 0.08
            }
        }

        return InferenceAdjustments(
            semanticAdjustments: semantic,
            intentAdjustments: intent,
            graphAdjustments: graph,
            entityAdjustments: entity,
            calibrationAdjustments: calibration
        )
    }

    // MARK: — 4. Confidence Recalibration

    static func recalibrateConfidence(
        nodeType: String,
        records: [CalibrationRecord]
    ) -> (scaleFactor: Double, offset: Double) {
        let relevant = records.filter { $0.nodeType == nodeType }
        guard relevant.count >= 3 else { return (1.0, 0) }

        let avgPredicted = relevant.map(\.predictedConfidence).reduce(0, +) / Double(relevant.count)
        let avgActual = relevant.map(\.actualCorrectness).reduce(0, +) / Double(relevant.count)

        // Simple linear recalibration: scale + offset to align predicted with actual
        let scaleFactor = avgActual / max(avgPredicted, 0.01)
        let offset = avgActual - avgPredicted * scaleFactor

        return (min(max(scaleFactor, 0.5), 1.5), max(min(offset, 0.3), -0.3))
    }

    // MARK: — 5. Rule Synthesis

    static func synthesizeRules(from patterns: [FailurePattern], adjustments: InferenceAdjustments) -> [SynthesizedRule] {
        var rules: [SynthesizedRule] = []
        var ruleId = 0

        for pattern in patterns where pattern.frequency >= 3 {
            // Rule: boost entity mapping when clipboard + spreadsheet pattern detected
            if pattern.affectedNodeTypes.contains("extract_fields") && pattern.affectedNodeTypes.contains("append_sheet_row") {
                ruleId += 1
                rules.append(SynthesizedRule(
                    id: "rule\(ruleId)", version: 1,
                    description: "If clipboard value contains currency AND next action is spreadsheet append → increase entity mapping confidence by +0.15",
                    condition: .init(field: "actionSequence", operator_: .contains, value: "extract_fields,append_sheet_row"),
                    action: .init(target: "entityMappingConfidence", operation: .add, value: 0.15, layer: .entity),
                    confidence: 0.82, evidenceCount: pattern.frequency,
                    createdAt: Date(), isReversible: true, rollbackRuleId: nil
                ))
            }

            // Rule: prioritize document entity extraction for Gmail+attachment patterns
            if pattern.affectedNodeTypes.contains("gmail_fetch") || pattern.affectedNodeTypes.contains("gmail_search") {
                ruleId += 1
                rules.append(SynthesizedRule(
                    id: "rule\(ruleId)", version: 1,
                    description: "If Gmail search is followed by attachment download → prioritize document entity extraction over keyword classification",
                    condition: .init(field: "actionSequence", operator_: .contains, value: "gmail_search,gmail_fetch"),
                    action: .init(target: "entityClassification:document", operation: .boostIf, value: 0.12, layer: .entity),
                    confidence: 0.78, evidenceCount: pattern.frequency,
                    createdAt: Date(), isReversible: true, rollbackRuleId: nil
                ))
            }

            // Rule: bias field mapping toward header similarity
            if pattern.primaryAffectedLayer == .entity {
                ruleId += 1
                rules.append(SynthesizedRule(
                    id: "rule\(ruleId)", version: 1,
                    description: "If spreadsheet headers are present → bias field mapping toward header similarity rather than action sequence",
                    condition: .init(field: "entityConfidence", operator_: .lessThan, value: "0.8"),
                    action: .init(target: "headerMatchingBias", operation: .add, value: 0.12, layer: .entity),
                    confidence: 0.75, evidenceCount: pattern.frequency,
                    createdAt: Date(), isReversible: true, rollbackRuleId: nil
                ))
            }
        }

        return rules
    }

    // MARK: — 6. Patch Assembly

    static func assemblePatch(
        name: String,
        description: String,
        from patterns: [FailurePattern],
        adjustments: InferenceAdjustments,
        rules: [SynthesizedRule],
        layer: ImprovementPatch.AffectedLayer,
        bundles: [DebugBundle]
    ) -> ImprovementPatch {
        let impact = estimateImpact(from: patterns, adjustments: adjustments, rules: rules, bundles: bundles)
        let regression = assessRegression(from: patterns, adjustments: adjustments, bundles: bundles)

        return ImprovementPatch(
            id: "patch_\(UUID().uuidString.prefix(8))",
            version: 1,
            name: name,
            description: description,
            createdAt: Date(),
            appliedAt: nil,
            status: .proposed,
            affectedLayer: layer,
            changeType: deriveChangeType(from: adjustments),
            adjustments: adjustments,
            rules: rules,
            expectedImpact: impact,
            regressionRisk: regression,
            rollbackKey: "rollback_\(UUID().uuidString.prefix(8))",
            isActive: false
        )
    }

    private static func deriveChangeType(from adjustments: InferenceAdjustments) -> ImprovementPatch.ChangeType {
        let hasWeights = !adjustments.semanticAdjustments.heuristicWeights.isEmpty ||
                         !adjustments.intentAdjustments.templateWeights.isEmpty ||
                         !adjustments.calibrationAdjustments.scaleFactors.isEmpty
        let hasRules = !adjustments.semanticAdjustments.ambiguityResolutionRules.isEmpty ||
                       !adjustments.graphAdjustments.nodeOrderingRules.isEmpty
        let hasCalibration = !adjustments.calibrationAdjustments.scaleFactors.isEmpty

        if hasWeights && hasRules && hasCalibration { return .combined }
        if hasWeights { return .weightAdjustment }
        if hasRules { return .ruleAddition }
        if hasCalibration { return .calibrationShift }
        return .heuristicTweak
    }

    private static func estimateImpact(
        from patterns: [FailurePattern],
        adjustments: InferenceAdjustments,
        rules: [SynthesizedRule],
        bundles: [DebugBundle]
    ) -> ImprovementPatch.ImpactEstimate {
        let affectedNodeTypes = Set(patterns.flatMap(\.affectedNodeTypes))
        let totalFailures = patterns.map(\.frequency).reduce(0, +)
        let avgSeverity = patterns.isEmpty ? 0 : patterns.map(\.averageSeverity).reduce(0, +) / Double(patterns.count)

        return ImprovementPatch.ImpactEstimate(
            expectedAccuracyGain: min(avgSeverity * 0.6, 0.30),
            affectedWorkflowCount: totalFailures,
            confidenceDeltaShift: -0.08,  // expect slight reduction in overconfidence
            nodeTypesImproved: Array(affectedNodeTypes),
            estimatedFalsePositiveReduction: min(Double(totalFailures) * 0.4 / Double(max(bundles.count, 1)), 0.5)
        )
    }

    private static func assessRegression(
        from patterns: [FailurePattern],
        adjustments: InferenceAdjustments,
        bundles: [DebugBundle]
    ) -> ImprovementPatch.RegressionAssessment {
        // Regression risk increases with: number of affected node types, number of heuristic tweaks
        let affectedTypes = Set(patterns.flatMap(\.affectedNodeTypes)).count
        let tweakCount = adjustments.semanticAdjustments.heuristicWeights.count +
                         adjustments.calibrationAdjustments.scaleFactors.count
        let risk = min(Double(affectedTypes) * 0.03 + Double(tweakCount) * 0.04, 0.5)

        return ImprovementPatch.RegressionAssessment(
            regressionRisk: risk,
            workflowsAtRisk: max(1, Int(Double(bundles.count) * risk)),
            potentiallyDegradedAreas: Array(patterns.flatMap(\.affectedNodeTypes).prefix(3))
        )
    }

    // MARK: — 7. Patch Simulation

    static func simulate(
        patch: ImprovementPatch,
        on bundles: [DebugBundle],
        calibrationRecords: [CalibrationRecord]
    ) -> SimulationResult {
        let relevantBundles = bundles.filter { bundle in
            !Set(patch.rules.flatMap { $0.description.components(separatedBy: " ") }).isDisjoint(with:
                Set(bundle.groundTruth.semanticActions.flatMap { [$0.output.action, $0.output.provider] }))
        }
        let testBundles = relevantBundles.isEmpty ? Array(bundles.prefix(min(10, bundles.count))) : relevantBundles

        var accuracyGains: [Double] = []
        var regressionCount = 0
        var regressionSeveritySum: Double = 0
        var affectedIds: [String] = []
        var confidenceShifts: [String: [Double]] = [:]

        for bundle in testBundles {
            let currentSeverity = bundle.failureReport.severityScore
            // Simulated: rules reduce severity proportionally to their confidence
            let totalRuleConfidence = patch.rules.map(\.confidence).reduce(0, +)
            let reduction = min(totalRuleConfidence * 0.15, currentSeverity * 0.8)
            let simulatedSeverity = currentSeverity - reduction

            if simulatedSeverity < currentSeverity {
                accuracyGains.append(currentSeverity - simulatedSeverity)
                affectedIds.append(bundle.sessionId)
            } else {
                regressionCount += 1
                regressionSeveritySum += abs(simulatedSeverity - currentSeverity)
            }

            // Track confidence shifts per node type
            for calRecord in calibrationRecords where bundle.sessionId == calRecord.sessionId {
                if let nodeType = calRecord.nodeType {
                    confidenceShifts[nodeType, default: []].append(
                        calRecord.predictedConfidence - calRecord.calibrationDelta * 0.5
                    )
                }
            }
        }

        let avgGain = accuracyGains.isEmpty ? 0 : accuracyGains.reduce(0, +) / Double(accuracyGains.count)
        let regressionSeverity = regressionCount > 0 ? regressionSeveritySum / Double(regressionCount) : 0
        let netGain = avgGain - regressionSeverity * 0.5

        let shifts: [String: Double] = confidenceShifts.mapValues { shifts in
            shifts.reduce(0, +) / Double(max(shifts.count, 1))
        }

        let recommendation: SimulationResult.PatchRecommendation
        if netGain > 0.05 && regressionCount == 0 { recommendation = .deploy }
        else if netGain > 0.02 && regressionCount <= 1 { recommendation = .deployWithCaution }
        else if netGain > 0 { recommendation = .revise }
        else { recommendation = .reject }

        return SimulationResult(
            patchId: patch.id, simulatedAt: Date(), testedOnDebugBundles: testBundles.count,
            accuracyGain: avgGain, regressionCount: regressionCount,
            regressionSeverity: regressionSeverity, netGain: netGain,
            affectedWorkflowIds: affectedIds, confidenceShiftPerNode: shifts,
            recommendation: recommendation
        )
    }

    // MARK: — 8. Continuous Learning Loop

    static func executeLearningLoop(
        bundles: [DebugBundle],
        calibrationRecords: [CalibrationRecord],
        state: inout LearningLoopState,
        deploymentThresholds: LearningLoopState.DeploymentThresholds? = nil
    ) -> LearningLoopResult {
        let thresholds = deploymentThresholds ?? state.deploymentThresholds
        state.loopCount += 1

        // Step 1: Mine patterns
        let patterns = minePatterns(from: bundles)
        guard !patterns.isEmpty else {
            state.lastLoopAt = Date()
            return LearningLoopResult(
                state: state, patchesGenerated: 0, patchesDeployed: 0,
                summary: "No recurring failure patterns detected. \(bundles.count) workflows evaluated."
            )
        }

        // Step 2: Generate signatures
        let signatures = generateSignatures(from: patterns, bundles: bundles)

        // Step 3: Generate adjustments
        let adjustments = generateAdjustments(from: patterns, signatures: signatures, calibrationRecords: calibrationRecords)

        // Step 4: Synthesize rules
        let rules = synthesizeRules(from: patterns, adjustments: adjustments)

        // Step 5: Assemble patch
        let primaryLayer = patterns.first?.primaryAffectedLayer ?? .semantic
        let patch = assemblePatch(
            name: "Auto-patch #\(state.loopCount): \(patterns.first?.name ?? "Unknown")",
            description: "Automatically generated from \(patterns.count) failure pattern(s) across \(bundles.count) workflows",
            from: patterns, adjustments: adjustments, rules: rules,
            layer: primaryLayer == .entity ? .entity : primaryLayer == .intent ? .intent : .multi,
            bundles: bundles
        )

        // Step 6: Simulate
        let simulation = simulate(patch: patch, on: bundles, calibrationRecords: calibrationRecords)

        var deployedCount = 0

        // Step 7: Deploy if safe
        if simulation.isSafe && patch.expectedImpact.expectedAccuracyGain > thresholds.minImprovementConfidence {
            var deployedPatch = patch
            deployedPatch.status = .applied
            deployedPatch.appliedAt = Date()
            deployedPatch.isActive = true
            state.activePatches.append(deployedPatch.id)
            state.totalPatchesApplied += 1
            state.totalPatchesGenerated += 1
            state.totalWorkflowsProcessed += bundles.count
            state.accumulatedGain += simulation.accuracyGain
            deployedCount = 1
        } else {
            state.totalPatchesGenerated += 1
            state.totalWorkflowsProcessed += bundles.count
        }

        // Step 8: Determine trend
        state.currentAccuracyTrend = simulation.netGain > 0.03 ? "improving"
            : simulation.netGain > 0 ? "stable"
            : "degrading"
        state.lastLoopAt = Date()

        return LearningLoopResult(
            state: state,
            patchesGenerated: 1,
            patchesDeployed: deployedCount,
            simulation: simulation,
            summary: buildLoopSummary(patterns: patterns, patch: patch, simulation: simulation, deployed: deployedCount > 0)
        )
    }

    private static func buildLoopSummary(
        patterns: [FailurePattern],
        patch: ImprovementPatch,
        simulation: SimulationResult,
        deployed: Bool
    ) -> String {
        let patternNames = patterns.map(\.name).joined(separator: "; ")
        let status = deployed ? "deployed" : "held (simulation recommendation: \(simulation.recommendation.rawValue))"
        return "Loop complete. \(patterns.count) pattern(s): \(patternNames). Patch '\(patch.name)' \(status). Expected gain: +\(String(format: "%.1f", simulation.accuracyGain * 100))% accuracy, regression risk: \(String(format: "%.1f", patch.regressionRisk.regressionRisk * 100))%."
    }

    // MARK: — 9. Full Compilation Pipeline

    static func compile(
        from bundles: [DebugBundle],
        calibrationRecords: [CalibrationRecord],
        state: inout LearningLoopState
    ) -> CompilationResult {
        let patterns = minePatterns(from: bundles)
        guard !patterns.isEmpty else {
            return CompilationResult(patterns: [], patches: [], simulationResults: [], summary: "No patterns to compile.")
        }

        let signatures = generateSignatures(from: patterns, bundles: bundles)
        let adjustments = generateAdjustments(from: patterns, signatures: signatures, calibrationRecords: calibrationRecords)
        let rules = synthesizeRules(from: patterns, adjustments: adjustments)

        var patches: [ImprovementPatch] = []
        var simulations: [SimulationResult] = []

        // Generate candidate patches per significant pattern
        for pattern in patterns where pattern.frequency >= 3 {
            let patch = assemblePatch(
                name: "Fix: \(pattern.name)",
                description: "Targeted fix for recurring \(pattern.primaryAffectedLayer.rawValue) failures",
                from: [pattern], adjustments: adjustments, rules: rules.filter { $0.evidenceCount >= 2 },
                layer: pattern.primaryAffectedLayer == .entity ? .entity :
                       pattern.primaryAffectedLayer == .intent ? .intent : .multi,
                bundles: bundles
            )
            let sim = simulate(patch: patch, on: bundles, calibrationRecords: calibrationRecords)

            if sim.isSafe {
                var deployed = patch
                deployed.status = .applied
                deployed.appliedAt = Date()
                deployed.isActive = true
                patches.append(deployed)
                state.activePatches.append(deployed.id)
                state.totalPatchesApplied += 1
                state.accumulatedGain += sim.accuracyGain
            } else {
                patches.append(patch)
            }
            simulations.append(sim)
            state.totalPatchesGenerated += 1
        }

        state.totalWorkflowsProcessed += bundles.count
        state.lastLoopAt = Date()
        state.currentAccuracyTrend = state.accumulatedGain > 0.05 ? "improving" : "stable"
        state.loopCount += 1

        return CompilationResult(
            patterns: patterns,
            patches: patches,
            simulationResults: simulations,
            summary: "Compiled \(patterns.count) pattern(s) into \(patches.count) patch(es). \(patches.filter(\.isActive).count) applied. Accumulated gain: +\(String(format: "%.1f", state.accumulatedGain * 100))% accuracy."
        )
    }
}

// MARK: — Result Types

struct LearningLoopResult: Codable {
    let state: LearningLoopState
    let patchesGenerated: Int
    let patchesDeployed: Int
    var simulation: SimulationResult?
    var summary: String
}

struct CompilationResult: Codable {
    let patterns: [FailurePattern]
    let patches: [ImprovementPatch]
    let simulationResults: [SimulationResult]
    let summary: String

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
