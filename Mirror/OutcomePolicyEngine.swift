import Foundation

// MARK: ═══════════════════════════════════════════
// MARK: 1 — Strategy Space
// MARK: ═══════════════════════════════════════════

struct StrategySet: Codable, Equatable, Hashable {
    var intentStrategy: IntentStrategy
    var entityStrategy: EntityResolutionStrategy
    var graphStrategy: GraphConstructionStrategy
    var extractionSensitivity: ExtractionSensitivity
    var providerStrategy: ProviderInterpretationStrategy
    var explorationTag: String?        // set when this was an exploratory choice

    static let `default` = StrategySet(
        intentStrategy: .hybridBalanced,
        entityStrategy: .balancedMerge,
        graphStrategy: .hybridGraph,
        extractionSensitivity: .balanced,
        providerStrategy: .fuzzyMapping
    )

    var fingerprint: String {
        "\(intentStrategy.rawValue)|\(entityStrategy.rawValue)|\(graphStrategy.rawValue)|\(extractionSensitivity.rawValue)|\(providerStrategy.rawValue)"
    }

    enum IntentStrategy: String, Codable, CaseIterable {
        case keywordFirst          // prioritize keyword matching over action sequences
        case entityFirst           // prioritize entity/artifact matching
        case actionSequenceFirst   // prioritize the order of actions
        case hybridBalanced         // equal weight to all signals
    }

    enum EntityResolutionStrategy: String, Codable, CaseIterable {
        case clipboardWeighted     // trust clipboard values more than headers
        case headerWeighted        // trust spreadsheet/document headers more
        case extractionHeavy       // aggressively extract all possible fields
        case conservativeMerge     // only merge entities with high confidence
        case balancedMerge         // middle ground
    }

    enum GraphConstructionStrategy: String, Codable, CaseIterable {
        case dataflowFirst         // prioritize data flow edges over control flow
        case actionFirst           // prioritize sequential action ordering
        case hybridGraph           // balance both
        case minimalChain           // only connect nodes with explicit data flow
    }

    enum ExtractionSensitivity: String, Codable, CaseIterable {
        case highPrecision         // fewer actions, higher individual confidence
        case highRecall             // more actions, lower individual confidence
        case balanced              // middle ground
    }

    enum ProviderInterpretationStrategy: String, Codable, CaseIterable {
        case strictMapping         // only use exact provider matches
        case fuzzyMapping          // allow similar providers (e.g. Chrome → generic browser)
        case fallbackEnabled       // allow desktop fallback when API uncertain
    }
}

// MARK: ═══════════════════════════════════════════
// MARK: 2 — Context Feature Vector
// MARK: ═══════════════════════════════════════════

struct ContextFeatureVector: Codable, Equatable {
    var providerMix: ProviderMix
    var clipboardDensity: FeatureBucket      // low / medium / high
    var textEntropy: FeatureBucket            // low / medium / high
    var spreadsheetPresence: Bool
    var documentPresence: Bool
    var actionSequenceLength: FeatureBucket   // short / medium / long
    var entityDensity: FeatureBucket          // few / medium / many entities
    var ambiguityScore: FeatureBucket         // low / medium / high ambiguity
    var gmailActionsPresent: Bool
    var sheetsActionsPresent: Bool
    var desktopActionsPresent: Bool

    enum FeatureBucket: String, Codable {
        case low, medium, high
    }

    struct ProviderMix: Codable, Equatable {
        var hasGmail: Bool
        var hasSheets: Bool
        var hasDesktop: Bool
        var hasBrowser: Bool
        var dominantProvider: String
    }

    /// Convert to a discrete cluster key for policy lookup
    var clusterKey: String {
        var parts: [String] = []
        parts.append("pm_\(dominantProviderPattern)")
        parts.append("sp_\(spreadsheetPresence ? "Y" : "N")")
        parts.append("dp_\(documentPresence ? "Y" : "N")")
        parts.append("as_\(actionSequenceLength.rawValue)")
        parts.append("ed_\(entityDensity.rawValue)")
        parts.append("am_\(ambiguityScore.rawValue)")
        return parts.joined(separator: "|")
    }

    private var dominantProviderPattern: String {
        if providerMix.hasGmail && providerMix.hasSheets { return "gmail+sheets" }
        if providerMix.hasSheets { return "sheets" }
        if providerMix.hasGmail { return "gmail" }
        if providerMix.hasDesktop && providerMix.hasBrowser { return "desktop+browser" }
        if providerMix.hasBrowser { return "browser" }
        if providerMix.hasDesktop { return "desktop" }
        return "unknown"
    }
}

// MARK: ═══════════════════════════════════════════
// MARK: 3 — Reward Function
// MARK: ═══════════════════════════════════════════

struct PolicyReward: Codable {
    let sessionId: String
    let timestamp: Date
    var totalReward: Double        // 0.0-1.0
    var components: RewardComponents

    struct RewardComponents: Codable {
        var executionSuccess: Double       // 0 or 1
        var entityMappingAccuracy: Double  // 0.0-1.0
        var intentAccuracy: Double         // 0.0-1.0
        var graphCoherenceScore: Double    // 0.0-1.0
        var failurePenalty: Double         // negative
        var userCorrectionPenalty: Double  // negative per correction
        var regressionPenalty: Double      // negative if outcome regressed
    }

    static func compute(from bundle: DebugBundle) -> PolicyReward {
        var components = RewardComponents(
            executionSuccess: 0,
            entityMappingAccuracy: 0,
            intentAccuracy: 0,
            graphCoherenceScore: 0,
            failurePenalty: 0,
            userCorrectionPenalty: 0,
            regressionPenalty: 0
        )

        // Execution success
        if bundle.groundTruth.verifiedOutcome?.success == true {
            components.executionSuccess = 1.0
        } else if bundle.groundTruth.verifiedOutcome != nil {
            components.executionSuccess = 0.3  // partial credit for running
        } else {
            components.executionSuccess = 0.7  // no outcome data = neutral
        }

        // Entity mapping accuracy from calibration records
        let entityRecords = bundle.calibrationRecords.filter { $0.layer == "entity" }
        if !entityRecords.isEmpty {
            components.entityMappingAccuracy = entityRecords.map(\.actualCorrectness).reduce(0, +) / Double(entityRecords.count)
        } else {
            components.entityMappingAccuracy = bundle.groundTruth.entityGraph.confidence
        }

        // Intent accuracy
        components.intentAccuracy = bundle.groundTruth.workflowIntent.confidence

        // Graph coherence
        components.graphCoherenceScore = bundle.diffReport?.overallSimilarity ?? 0.5

        // Failure penalty
        let severityWeight = bundle.failureReport.severityScore
        components.failurePenalty = -severityWeight * 0.3

        // User correction penalty
        let correctionCount = bundle.groundTruth.userCorrections.count
        components.userCorrectionPenalty = -Double(correctionCount) * 0.05

        // Regression penalty (if this workflow got worse than a prior run)
        if bundle.failureReport.severityScore > 0.5 && bundle.failureReport.totalFailures > 2 {
            components.regressionPenalty = -0.1
        }

        let total = (
            components.executionSuccess * 0.30 +
            components.entityMappingAccuracy * 0.25 +
            components.intentAccuracy * 0.20 +
            components.graphCoherenceScore * 0.15 +
            components.failurePenalty +
            components.userCorrectionPenalty +
            components.regressionPenalty
        )
        let clamped = min(max(total, 0), 1.0)

        return PolicyReward(
            sessionId: bundle.sessionId,
            timestamp: Date(),
            totalReward: clamped,
            components: components
        )
    }
}

// MARK: ═══════════════════════════════════════════
// MARK: 4 — Strategy Score Table
// MARK: ═══════════════════════════════════════════

struct StrategyScoreEntry: Codable, Identifiable {
    let id: String
    let contextCluster: String
    let strategyFingerprint: String
    var strategy: StrategySet
    var score: Double                      // estimated reward
    var sampleCount: Int                   // how many times tried
    var confidenceInterval: ConfidenceInterval
    var lastUpdated: Date
    var isStable: Bool
    var driftDetected: Bool

    struct ConfidenceInterval: Codable {
        var low: Double
        var high: Double
    }

    var explorationPriority: Double {
        // UCB-style: score + exploration bonus for under-sampled strategies
        if sampleCount < 3 { return 1.0 }
        let explorationBonus = 1.0 / sqrt(Double(sampleCount))
        return score + explorationBonus
    }
}

struct StrategyScoreTable: Codable {
    var entries: [String: StrategyScoreEntry]  // key = "\(clusterKey)|\(fingerprint)"
    var lastCompactionAt: Date
    var totalEvaluations: Int
    var averageReward: Double

    mutating func record(
        context: ContextFeatureVector,
        strategy: StrategySet,
        reward: PolicyReward,
        learningRate: Double = 0.1
    ) {
        let key = "\(context.clusterKey)|\(strategy.fingerprint)"
        let now = Date()

        if var entry = entries[key] {
            // Exponential moving average update
            let oldWeight = 1.0 - learningRate
            entry.score = entry.score * oldWeight + reward.totalReward * learningRate
            entry.sampleCount += 1

            // Update confidence interval (simplified: ±0.2/√n)
            let margin = 0.2 / sqrt(Double(entry.sampleCount))
            entry.confidenceInterval = .init(low: max(0, entry.score - margin), high: min(1, entry.score + margin))
            entry.isStable = margin < 0.05
            entry.lastUpdated = now

            // Drift detection: if score moved >0.1 from 3-updates-ago average
            entry.driftDetected = abs(reward.totalReward - entry.score) > 0.15

            entries[key] = entry
        } else {
            entries[key] = StrategyScoreEntry(
                id: "sse_\(UUID().uuidString.prefix(8))",
                contextCluster: context.clusterKey,
                strategyFingerprint: strategy.fingerprint,
                strategy: strategy,
                score: reward.totalReward,
                sampleCount: 1,
                confidenceInterval: .init(low: max(0, reward.totalReward - 0.2), high: min(1, reward.totalReward + 0.2)),
                lastUpdated: now,
                isStable: false,
                driftDetected: false
            )
        }

        totalEvaluations += 1
        averageReward = entries.values.map(\.score).reduce(0, +) / Double(max(entries.count, 1))
    }

    func bestStrategy(for context: ContextFeatureVector) -> (StrategySet, StrategyScoreEntry)? {
        let clusterKey = context.clusterKey
        let candidates = entries.values.filter { $0.contextCluster == clusterKey }

        // If no data for this exact cluster, try similar clusters
        let effective = candidates.isEmpty
            ? entries.values.filter { $0.contextCluster.components(separatedBy: "|").first == clusterKey.components(separatedBy: "|").first }
            : candidates

        guard !effective.isEmpty else { return nil }

        let best = effective.max(by: { $0.score < $1.score })!
        return (best.strategy, best)
    }

    func contextPerformance(context: ContextFeatureVector) -> ContextPerformance {
        let clusterKey = context.clusterKey
        let candidates = entries.values.filter { $0.contextCluster == clusterKey }
        let scores = candidates.map(\.score)
        let avg = scores.isEmpty ? 0 : scores.reduce(0, +) / Double(scores.count)

        return ContextPerformance(
            clusterKey: clusterKey,
            strategyCount: candidates.count,
            evaluations: candidates.map(\.sampleCount).reduce(0, +),
            averageScore: avg,
            bestStrategy: candidates.max(by: { $0.score < $1.score })?.strategy.fingerprint,
            worstStrategy: candidates.min(by: { $0.score < $1.score })?.strategy.fingerprint
        )
    }
}

struct ContextPerformance: Codable {
    let clusterKey: String
    let strategyCount: Int
    let evaluations: Int
    let averageScore: Double
    let bestStrategy: String?
    let worstStrategy: String?
}

// MARK: ═══════════════════════════════════════════
// MARK: 5 — Outcome Policy Engine
// MARK: ═══════════════════════════════════════════

struct OutcomePolicyEngine {

    // MARK: — Context Extraction

    static func extractContext(
        from actions: [SemanticAction],
        artifacts: [ExtractedArtifact] = [],
        events: [EventTapManager.CapturedEvent] = []
    ) -> ContextFeatureVector {
        let providers = Set(actions.map(\.provider))
        let hasGmail = providers.contains("gmail")
        let hasSheets = providers.contains("sheets")
        let hasDesktop = providers.contains { p in
            !["gmail", "sheets", "browser", "chrome"].contains(p)
        }
        let hasBrowser = providers.contains("browser") || providers.contains("chrome")

        // Dominant provider
        var providerCounts: [String: Int] = [:]
        for action in actions { providerCounts[action.provider, default: 0] += 1 }
        let dominant = providerCounts.max(by: { $0.value < $1.value })?.key ?? "unknown"

        // Clipboard density: how many clipboard events per action
        let clipboardEvents = events.filter { $0.type == "clipboardChange" }.count
        let clipboardRatio = actions.count > 0 ? Double(clipboardEvents) / Double(actions.count) : 0
        let clipboardDensity: ContextFeatureVector.FeatureBucket =
            clipboardRatio > 0.5 ? .high : clipboardRatio > 0.2 ? .medium : .low

        // Text entropy: variety of typed text
        let typedTexts = actions.compactMap { $0.payload.typedText }
        let uniqueChars = Set(typedTexts.joined()).count
        let textEntropy: ContextFeatureVector.FeatureBucket =
            uniqueChars > 50 ? .high : uniqueChars > 20 ? .medium : .low

        // Action length
        let count = actions.count
        let actionLength: ContextFeatureVector.FeatureBucket =
            count > 5 ? .high : count > 3 ? .medium : .low

        // Entity density
        let entityCount = artifacts.count
        let entityDensity: ContextFeatureVector.FeatureBucket =
            entityCount > 3 ? .high : entityCount > 1 ? .medium : .low

        // Ambiguity: average action confidence
        let avgConf = actions.isEmpty ? 0 : actions.map(\.confidence).reduce(0, +) / Double(actions.count)
        let ambiguity: ContextFeatureVector.FeatureBucket =
            avgConf < 0.5 ? .high : avgConf < 0.75 ? .medium : .low

        return ContextFeatureVector(
            providerMix: ContextFeatureVector.ProviderMix(
                hasGmail: hasGmail, hasSheets: hasSheets,
                hasDesktop: hasDesktop, hasBrowser: hasBrowser,
                dominantProvider: dominant
            ),
            clipboardDensity: clipboardDensity,
            textEntropy: textEntropy,
            spreadsheetPresence: hasSheets,
            documentPresence: artifacts.contains { $0.sourceApp == "gmail" },
            actionSequenceLength: actionLength,
            entityDensity: entityDensity,
            ambiguityScore: ambiguity,
            gmailActionsPresent: hasGmail,
            sheetsActionsPresent: hasSheets,
            desktopActionsPresent: hasDesktop
        )
    }

    // MARK: — Strategy Selection

    static func selectStrategy(
        for context: ContextFeatureVector,
        from table: StrategyScoreTable,
        explorationRate: Double = 0.10
    ) -> StrategySet {
        // Epsilon-greedy: explore with probability = explorationRate
        if Double.random(in: 0...1) < explorationRate {
            return StrategySet.randomExploratory()
        }

        // Exploit: pick best known strategy for this context
        if let (strategy, _) = table.bestStrategy(for: context) {
            return strategy
        }

        // Fallback: default strategy
        return .default
    }

    // MARK: — Feedback Loop

    static func ingestFeedback(
        bundle: DebugBundle,
        context: ContextFeatureVector,
        strategy: StrategySet,
        table: inout StrategyScoreTable
    ) {
        let reward = PolicyReward.compute(from: bundle)

        // Boost reward for strategies that match the context's characteristics
        var adjustedReward = reward
        if strategy.entityStrategy == .headerWeighted && context.spreadsheetPresence {
            adjustedReward.totalReward = min(adjustedReward.totalReward + 0.03, 1.0)
        }
        if strategy.graphStrategy == .dataflowFirst && context.clipboardDensity == .high {
            adjustedReward.totalReward = min(adjustedReward.totalReward + 0.02, 1.0)
        }
        if strategy.intentStrategy == .keywordFirst && context.textEntropy == .low {
            adjustedReward.totalReward = min(adjustedReward.totalReward + 0.02, 1.0)
        }

        table.record(context: context, strategy: strategy, reward: adjustedReward)
    }

    // MARK: — Context-Strength Analysis

    static func analyzeContextStrength(
        context: ContextFeatureVector,
        table: StrategyScoreTable
    ) -> StrategyRecommendation {
        var recommendations: [StrategyRecommendation.DimensionRec] = []

        // Test each strategy dimension independently
        for intentStrat in StrategySet.IntentStrategy.allCases {
            for entityStrat in StrategySet.EntityResolutionStrategy.allCases {
                var testStrategy = StrategySet.default
                testStrategy.intentStrategy = intentStrat
                testStrategy.entityStrategy = entityStrat

                let key = "\(context.clusterKey)|\(testStrategy.fingerprint)"
                if let entry = table.entries[key], entry.sampleCount >= 2 {
                    if entry.score > table.averageReward + 0.05 {
                        recommendations.append(StrategyRecommendation.DimensionRec(
                            dimension: "intent_entity_pair",
                            recommended: "intent=\(intentStrat.rawValue), entity=\(entityStrat.rawValue)",
                            lift: entry.score - table.averageReward,
                            confidence: Double(entry.sampleCount) / 10.0,
                            sampleCount: entry.sampleCount
                        ))
                    }
                }
            }
        }

        let bestRec = recommendations.max(by: { $0.lift < $1.lift })

        return StrategyRecommendation(
            context: context.clusterKey,
            topLift: bestRec?.lift ?? 0,
            recommendations: recommendations.sorted { $0.lift > $1.lift }.prefix(5).map { $0 }
        )
    }

    struct StrategyRecommendation: Codable {
        let context: String
        let topLift: Double
        let recommendations: [DimensionRec]

        struct DimensionRec: Codable {
            let dimension: String
            let recommended: String
            let lift: Double
            let confidence: Double
            let sampleCount: Int
        }
    }

    // MARK: — Safety Constraints

    static func validateStrategy(
        _ strategy: StrategySet,
        for context: ContextFeatureVector
    ) -> StrategyValidation {
        var warnings: [String] = []

        // Conservative merge is safer for high-ambiguity contexts
        if context.ambiguityScore == .high && strategy.entityStrategy == .extractionHeavy {
            warnings.append("High ambiguity with aggressive extraction — prefer conservativeMerge to avoid entity errors")
        }

        // Action-first can be fragile with long sequences
        if context.actionSequenceLength == .high && strategy.graphStrategy == .actionFirst {
            warnings.append("Long action sequence with action-first graph — prefer dataflowFirst for reliability")
        }

        // Fuzzy mapping risks provider misidentification
        if context.desktopActionsPresent && strategy.providerStrategy == .fuzzyMapping {
            warnings.append("Desktop actions present with fuzzy provider mapping — may misidentify apps")
        }

        return StrategyValidation(
            isSafe: warnings.count <= 1,
            warnings: warnings,
            overrideAllowed: true
        )
    }

    struct StrategyValidation: Codable {
        let isSafe: Bool
        let warnings: [String]
        let overrideAllowed: Bool
    }

    // MARK: — Policy State Persistence

    static func saveTable(_ table: StrategyScoreTable) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(table),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    static func loadTable(from json: String) -> StrategyScoreTable {
        guard let data = json.data(using: .utf8),
              let table = try? JSONDecoder().decode(StrategyScoreTable.self, from: data) else {
            return StrategyScoreTable(entries: [:], lastCompactionAt: Date(), totalEvaluations: 0, averageReward: 0)
        }
        return table
    }

    // MARK: — Policy Summary for AI

    static func buildPolicySummary(
        context: ContextFeatureVector,
        selectedStrategy: StrategySet,
        table: StrategyScoreTable,
        validation: StrategyValidation
    ) -> String {
        let perf = table.contextPerformance(context: context)
        var lines: [String] = []

        lines.append("## Policy Decision")
        lines.append("Context: \(context.clusterKey)")
        lines.append("Selected strategy: \(selectedStrategy.fingerprint)")
        lines.append("")

        if let best = perf.bestStrategy {
            let entry = table.entries.values.first { $0.strategyFingerprint == best }
            lines.append("Best known: \(best) — score: \(String(format: "%.2f", entry?.score ?? 0)) (\(entry?.sampleCount ?? 0) samples)")
        }
        lines.append("Evaluations in this context: \(perf.evaluations)")
        lines.append("Average score: \(String(format: "%.2f", perf.averageScore))")
        lines.append("")

        if !validation.warnings.isEmpty {
            lines.append("### Warnings")
            for warning in validation.warnings {
                lines.append("- \(warning)")
            }
            lines.append("")
        }

        lines.append("---")
        return lines.joined(separator: "\n")
    }
}

// MARK: — Strategy Random Exploration

extension StrategySet {
    static func randomExploratory() -> StrategySet {
        var s = StrategySet(
            intentStrategy: IntentStrategy.allCases.randomElement()!,
            entityStrategy: EntityResolutionStrategy.allCases.randomElement()!,
            graphStrategy: GraphConstructionStrategy.allCases.randomElement()!,
            extractionSensitivity: ExtractionSensitivity.allCases.randomElement()!,
            providerStrategy: ProviderInterpretationStrategy.allCases.randomElement()!,
            explorationTag: nil
        )
        s.explorationTag = "explore_\(UUID().uuidString.prefix(6))"
        return s
    }
}

// MARK: ═══════════════════════════════════════════
// MARK: 6 — Hypothesis Probability System
// MARK: ═══════════════════════════════════════════

struct WorkflowHypothesis: Codable, Identifiable, Hashable {
    let id: String
    var objective: String
    var domain: String
    var actionSequence: [String]           // ordered action types
    var providerMix: [String]              // providers involved
    var entityTypes: [String]              // entity types extracted
    var confidence: Double                 // this hypothesis's confidence
    var source: HypothesisSource

    enum HypothesisSource: String, Codable {
        case aiGenerated
        case heuristicExtracted
        case userProvided
        case blended
    }

    var fingerprint: String {
        "\(objective)|\(actionSequence.joined(separator: ","))"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(fingerprint)
    }

    static func == (lhs: WorkflowHypothesis, rhs: WorkflowHypothesis) -> Bool {
        lhs.fingerprint == rhs.fingerprint
    }
}

struct HypothesisDistribution: Codable {
    var contextCluster: String
    var strategyFingerprint: String
    var hypotheses: [String: HypothesisProbability]   // hypothesisId → probability
    var totalProbabilityMass: Double                   // should sum to ~1.0
    var sampleCount: Int
    var lastUpdated: Date
    var entropy: Double                               // higher = more uncertain

    struct HypothesisProbability: Codable {
        var probability: Double
        var confidence: Double
        var timesSelected: Int
        var timesCorrect: Int
        var averageReward: Double
        var lastSelectedAt: Date?
    }

    /// Bayesian update: shift probability mass toward hypotheses that produced higher reward
    mutating func update(hypothesisId: String, reward: PolicyReward, learningRate: Double = 0.15) {
        guard var entry = hypotheses[hypothesisId] else {
            // New hypothesis: initialize with reward-based prior
            hypotheses[hypothesisId] = HypothesisProbability(
                probability: reward.totalReward,
                confidence: 0.5,
                timesSelected: 1,
                timesCorrect: reward.totalReward > 0.7 ? 1 : 0,
                averageReward: reward.totalReward,
                lastSelectedAt: Date()
            )
            renormalize()
            sampleCount += 1
            lastUpdated = Date()
            return
        }

        // Update the selected hypothesis
        let oldProb = entry.probability
        let rewardSignal = reward.totalReward
        entry.probability = oldProb * (1 - learningRate) + rewardSignal * learningRate
        entry.timesSelected += 1
        if reward.totalReward > 0.7 { entry.timesCorrect += 1 }
        entry.averageReward = (entry.averageReward * Double(entry.timesSelected - 1) + reward.totalReward) / Double(entry.timesSelected)
        entry.lastSelectedAt = Date()
        entry.confidence = min(entry.confidence + learningRate * (rewardSignal > 0.6 ? 0.05 : -0.03), 1.0)
        hypotheses[hypothesisId] = entry

        // Penalize all non-selected hypotheses (their probability drifts down slightly)
        for key in hypotheses.keys where key != hypothesisId {
            var other = hypotheses[key]!
            other.probability *= (1 - learningRate * 0.3)
            other.confidence = max(0, other.confidence - 0.01)
            hypotheses[key] = other
        }

        renormalize()
        sampleCount += 1
        lastUpdated = Date()
    }

    private mutating func renormalize() {
        let sum = hypotheses.values.map(\.probability).reduce(0, +)
        guard sum > 0 else {
            // Uniform distribution
            let uniform = 1.0 / Double(max(hypotheses.count, 1))
            for key in hypotheses.keys {
                hypotheses[key]?.probability = uniform
            }
            totalProbabilityMass = 1.0
            return
        }
        for key in hypotheses.keys {
            hypotheses[key]?.probability /= sum
        }
        totalProbabilityMass = 1.0

        // Compute entropy: -Σ p * log(p)
        entropy = -hypotheses.values.map { p in
            p.probability > 0 ? p.probability * log(p.probability) : 0
        }.reduce(0, +)
    }

    func topHypothesis() -> (id: String, probability: Double)? {
        hypotheses.max(by: { $0.value.probability < $1.value.probability })
            .map { ($0.key, $0.value.probability) }
    }

    func topK(_ k: Int) -> [(id: String, prob: Double, avgReward: Double, timesCorrect: Int)] {
        hypotheses
            .sorted { $0.value.probability > $1.value.probability }
            .prefix(k)
            .map { ($0.key, $0.value.probability, $0.value.averageReward, $0.value.timesCorrect) }
    }

    func isConfident(threshold: Double = 0.7) -> Bool {
        guard let top = topHypothesis() else { return false }
        return top.probability > threshold
    }
}

// MARK: — Hypothesis Table (persists across sessions)

struct HypothesisTable: Codable {
    var distributions: [String: HypothesisDistribution]  // key = "\(contextCluster)|\(strategyFingerprint)"
    var totalHypothesesTracked: Int
    var lastCompactionAt: Date

    mutating func record(
        hypothesis: WorkflowHypothesis,
        context: ContextFeatureVector,
        strategy: StrategySet,
        reward: PolicyReward
    ) {
        let key = "\(context.clusterKey)|\(strategy.fingerprint)"
        var dist = distributions[key] ?? HypothesisDistribution(
            contextCluster: context.clusterKey,
            strategyFingerprint: strategy.fingerprint,
            hypotheses: [:],
            totalProbabilityMass: 0,
            sampleCount: 0,
            lastUpdated: Date(),
            entropy: 0
        )
        dist.update(hypothesisId: hypothesis.id, reward: reward)
        distributions[key] = dist
        totalHypothesesTracked = distributions.values.flatMap(\.hypotheses.keys).count
    }

    func bestHypothesis(
        for context: ContextFeatureVector,
        strategy: StrategySet
    ) -> (WorkflowHypothesis, Double)? {
        let key = "\(context.clusterKey)|\(strategy.fingerprint)"
        guard let dist = distributions[key],
              dist.topHypothesis() != nil else {
            return nil
        }
        // Return a placeholder — the actual hypothesis objects are stored externally
        // (this table stores probabilities, the hypothesis store has the full objects)
        return nil
    }

    func distribution(
        for context: ContextFeatureVector,
        strategy: StrategySet
    ) -> HypothesisDistribution? {
        let key = "\(context.clusterKey)|\(strategy.fingerprint)"
        return distributions[key]
    }
}

// MARK: — Hypothesis Selector

struct HypothesisSelector {

    /// Select the best hypothesis given context and strategy.
    /// Uses a Bayesian decision rule: argmax P(hypothesis | context, strategy, reward history)
    static func select(
        from candidates: [WorkflowHypothesis],
        context: ContextFeatureVector,
        strategy: StrategySet,
        table: HypothesisTable
    ) -> (selected: WorkflowHypothesis, isConfident: Bool, alternatives: [WorkflowHypothesis]) {
        let dist = table.distribution(for: context, strategy: strategy)

        // Score each candidate: prior from distribution × hypothesis confidence
        var scored: [(hypothesis: WorkflowHypothesis, score: Double)] = []

        for candidate in candidates {
            var score = candidate.confidence

            if let dist = dist,
               let history = dist.hypotheses[candidate.id] {
                // Bayes: likelihood (reward history) × prior (hypothesis confidence)
                let likelihood = history.averageReward
                let prior = history.probability
                score = likelihood * 0.6 + prior * 0.3 + candidate.confidence * 0.1
            }

            scored.append((candidate, score))
        }

        scored.sort { $0.score > $1.score }

        guard let best = scored.first else {
            return (candidates.first ?? WorkflowHypothesis(
                id: "fallback", objective: "unknown", domain: "general",
                actionSequence: [], providerMix: [], entityTypes: [],
                confidence: 0, source: .heuristicExtracted
            ), false, [])
        }

        let isConfident = dist?.isConfident() ?? false
        let alternatives = scored.dropFirst().prefix(3).map(\.hypothesis)

        return (best.hypothesis, isConfident, Array(alternatives))
    }

    /// Thompson sampling variant: sample hypothesis proportional to its reward distribution
    static func thompsonSample(
        from candidates: [WorkflowHypothesis],
        context: ContextFeatureVector,
        strategy: StrategySet,
        table: HypothesisTable
    ) -> WorkflowHypothesis {
        let dist = table.distribution(for: context, strategy: strategy)
        let defaultHypothesis = candidates.first ?? WorkflowHypothesis(
            id: "fallback", objective: "unknown", domain: "general",
            actionSequence: [], providerMix: [], entityTypes: [],
            confidence: 0, source: .heuristicExtracted
        )

        guard let dist = dist, candidates.count > 1 else { return defaultHypothesis }

        // For each candidate, sample from Beta(α=timesCorrect+1, β=timesWrong+1)
        var bestSample = -Double.infinity
        var bestCandidate = defaultHypothesis

        for candidate in candidates {
            if let history = dist.hypotheses[candidate.id] {
                // Approximate Beta sampling using reward history
                let sample = history.averageReward + (Double.random(in: -0.1...0.1) / sqrt(Double(max(history.timesSelected, 1))))
                if sample > bestSample {
                    bestSample = sample
                    bestCandidate = candidate
                }
            }
        }

        return bestCandidate
    }
}

// MARK: — Integrated Hypothesis-Aware Policy (extends OutcomePolicyEngine)

extension OutcomePolicyEngine {

    /// Full policy decision: strategy + hypothesis selection
    static func decideStrategyAndHypothesis(
        context: ContextFeatureVector,
        hypotheses: [WorkflowHypothesis],
        strategyTable: StrategyScoreTable,
        hypothesisTable: HypothesisTable,
        explorationRate: Double = 0.10
    ) -> PolicyDecision {
        // Step 1: Select strategy
        let strategy = selectStrategy(for: context, from: strategyTable, explorationRate: explorationRate)
        let validation = validateStrategy(strategy, for: context)

        // Step 2: Select hypothesis given context + strategy
        let (hypothesis, isConfident, alternatives) = HypothesisSelector.select(
            from: hypotheses, context: context, strategy: strategy, table: hypothesisTable
        )

        // Step 3: If not confident enough, fall back to Thompson sampling
        let finalHypothesis: WorkflowHypothesis
        if !isConfident && !hypotheses.isEmpty {
            finalHypothesis = HypothesisSelector.thompsonSample(
                from: hypotheses, context: context, strategy: strategy, table: hypothesisTable
            )
        } else {
            finalHypothesis = hypothesis
        }

        let dist = hypothesisTable.distribution(for: context, strategy: strategy)

        return PolicyDecision(
            context: context,
            selectedStrategy: strategy,
            selectedHypothesis: finalHypothesis,
            isConfident: isConfident,
            alternativeHypotheses: alternatives,
            entropy: dist?.entropy ?? 0,
            validation: validation
        )
    }

    /// Full feedback ingestion: update both strategy table and hypothesis distribution
    static func ingestFullFeedback(
        bundle: DebugBundle,
        context: ContextFeatureVector,
        strategy: StrategySet,
        selectedHypothesis: WorkflowHypothesis,
        strategyTable: inout StrategyScoreTable,
        hypothesisTable: inout HypothesisTable
    ) {
        let reward = PolicyReward.compute(from: bundle)
        ingestFeedback(bundle: bundle, context: context, strategy: strategy, table: &strategyTable)
        hypothesisTable.record(hypothesis: selectedHypothesis, context: context, strategy: strategy, reward: reward)
    }
}

struct PolicyDecision: Codable {
    let context: ContextFeatureVector
    let selectedStrategy: StrategySet
    let selectedHypothesis: WorkflowHypothesis
    let isConfident: Bool
    let alternativeHypotheses: [WorkflowHypothesis]
    let entropy: Double
    let validation: OutcomePolicyEngine.StrategyValidation

    var summary: String {
        var lines: [String] = []
        lines.append("Policy Decision: \(selectedHypothesis.objective) (\(selectedHypothesis.domain))")
        lines.append("  Confidence: \(isConfident ? "high" : "low") | Entropy: \(String(format: "%.2f", entropy))")
        lines.append("  Strategy: \(selectedStrategy.fingerprint)")
        lines.append("  Hypothesis: \(selectedHypothesis.actionSequence.joined(separator: " → "))")
        if !alternativeHypotheses.isEmpty {
            lines.append("  Alternatives:")
            for alt in alternativeHypotheses.prefix(3) {
                lines.append("    - \(alt.objective) (\(alt.domain)) [conf: \(String(format: "%.0f", alt.confidence * 100))%]")
            }
        }
        if !validation.warnings.isEmpty {
            lines.append("  Warnings:")
            for w in validation.warnings { lines.append("    - \(w)") }
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: — Hypothesis Builder (creates hypotheses from extraction pipeline outputs)

struct HypothesisBuilder {

    /// Build competing hypotheses from the same recording by varying strategy parameters.
    /// Each strategy set produces a different interpretation of the same raw events.
    static func buildHypotheses(
        from actions: [SemanticAction],
        intent: WorkflowIntent,
        artifacts: [ExtractedArtifact] = [],
        graph: WorkflowGraph? = nil
    ) -> [WorkflowHypothesis] {
        var hypotheses: [WorkflowHypothesis] = []

        // Primary hypothesis: what the system actually produced
        hypotheses.append(WorkflowHypothesis(
            id: "hyp_primary",
            objective: intent.objective,
            domain: intent.domain,
            actionSequence: actions.map(\.action),
            providerMix: Array(Set(actions.map(\.provider))),
            entityTypes: artifacts.map(\.artifactType),
            confidence: intent.confidence,
            source: .aiGenerated
        ))

        // Alternative: keyword-first interpretation (if different from primary)
        if intent.domain == "general" || intent.confidence < 0.7 {
            let keywordIntent = inferKeywordBasedIntent(from: actions)
            if keywordIntent.objective != intent.objective {
                hypotheses.append(WorkflowHypothesis(
                    id: "hyp_keyword",
                    objective: keywordIntent.objective,
                    domain: keywordIntent.domain,
                    actionSequence: actions.map(\.action),
                    providerMix: Array(Set(actions.map(\.provider))),
                    entityTypes: artifacts.map(\.artifactType),
                    confidence: keywordIntent.confidence,
                    source: .heuristicExtracted
                ))
            }
        }

        // Alternative: entity-first interpretation
        if !artifacts.isEmpty && intent.confidence < 0.8 {
            let entityIntent = inferEntityBasedIntent(from: artifacts, actions: actions)
            if entityIntent.objective != intent.objective {
                hypotheses.append(WorkflowHypothesis(
                    id: "hyp_entity",
                    objective: entityIntent.objective,
                    domain: entityIntent.domain,
                    actionSequence: actions.map(\.action),
                    providerMix: Array(Set(actions.map(\.provider))),
                    entityTypes: artifacts.map(\.artifactType),
                    confidence: entityIntent.confidence,
                    source: .heuristicExtracted
                ))
            }
        }

        // Alternative: minimal interpretation (fewer steps, higher confidence per step)
        let minimalConfidence = actions.filter { $0.confidence > 0.7 }
        if minimalConfidence.count < actions.count && minimalConfidence.count >= 1 {
            let minimalIntent = inferMinimalIntent(from: Array(minimalConfidence))
            if minimalIntent.objective != intent.objective {
                hypotheses.append(WorkflowHypothesis(
                    id: "hyp_minimal",
                    objective: minimalIntent.objective,
                    domain: minimalIntent.domain,
                    actionSequence: minimalConfidence.map(\.action),
                    providerMix: Array(Set(minimalConfidence.map(\.provider))),
                    entityTypes: artifacts.map(\.artifactType),
                    confidence: minimalConfidence.map(\.confidence).reduce(0, +) / Double(minimalConfidence.count),
                    source: .heuristicExtracted
                ))
            }
        }

        return hypotheses
    }

    private static func inferKeywordBasedIntent(from actions: [SemanticAction]) -> WorkflowIntent {
        let text = actions.compactMap { $0.payload.typedText ?? $0.payload.query }.joined(separator: " ").lowercased()
        if text.contains("invoice") || text.contains("payment") { return .init(objective: "invoice_processing", domain: "accounts_payable", description: "Keyword-based: invoice detected", confidence: 0.55, triggerPattern: "manual", frequency: "on_demand", estimatedDuration: 15) }
        if text.contains("lead") || text.contains("contact") { return .init(objective: "lead_tracking", domain: "lead_generation", description: "Keyword-based: lead detected", confidence: 0.55, triggerPattern: "manual", frequency: "on_demand", estimatedDuration: 15) }
        return .init(objective: "generic_workflow", domain: "general", description: "Keyword-based: generic", confidence: 0.40, triggerPattern: "manual", frequency: "on_demand", estimatedDuration: 15)
    }

    private static func inferEntityBasedIntent(from artifacts: [ExtractedArtifact], actions: [SemanticAction]) -> WorkflowIntent {
        let types = Set(artifacts.map(\.artifactType))
        if types.contains("invoice_tracker") || types.contains("invoice_email") { return .init(objective: "invoice_processing", domain: "accounts_payable", description: "Entity-based: invoice artifacts", confidence: 0.60, triggerPattern: "manual", frequency: "on_demand", estimatedDuration: 15) }
        if types.contains("lead_list") { return .init(objective: "lead_generation", domain: "lead_generation", description: "Entity-based: lead artifacts", confidence: 0.60, triggerPattern: "manual", frequency: "on_demand", estimatedDuration: 15) }
        return .init(objective: "generic_workflow", domain: "general", description: "Entity-based: generic", confidence: 0.45, triggerPattern: "manual", frequency: "on_demand", estimatedDuration: 15)
    }

    private static func inferMinimalIntent(from actions: [SemanticAction]) -> WorkflowIntent {
        let providers = Set(actions.map(\.provider))
        if providers.contains("gmail") && providers.contains("sheets") { return .init(objective: "email_to_sheet", domain: "data_transfer", description: "Minimal: email → sheet", confidence: 0.50, triggerPattern: "manual", frequency: "on_demand", estimatedDuration: 10) }
        if providers.contains("gmail") { return .init(objective: "email_workflow", domain: "email", description: "Minimal: email workflow", confidence: 0.45, triggerPattern: "manual", frequency: "on_demand", estimatedDuration: 10) }
        return .init(objective: "generic_workflow", domain: "general", description: "Minimal: generic", confidence: 0.35, triggerPattern: "manual", frequency: "on_demand", estimatedDuration: 10)
    }
}
