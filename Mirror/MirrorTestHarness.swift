import Foundation

// MARK: - Testing Harness

struct MirrorTestHarness {

    // MARK: - Sample Workflow 1: Invoice Processing (Gmail → Sheets)

    static func sampleInvoiceWorkflow() -> [EventTapManager.CapturedEvent] {
        let baseTime: Double = 1000.0
        var events: [EventTapManager.CapturedEvent] = []

        // Open Chrome, navigate to Gmail
        events.append(.init(timestamp: baseTime + 0, type: "mouseMoved", position: ["x": 800, "y": 44], targetApp: "Google Chrome", targetURL: nil))
        events.append(.init(timestamp: baseTime + 1, type: "mouseDown", position: ["x": 800, "y": 44], targetApp: "Google Chrome", targetURL: "https://mail.google.com"))
        events.append(.init(timestamp: baseTime + 2, type: "keyDown", characters: "i", targetApp: "Google Chrome", targetURL: "https://mail.google.com"))
        events.append(.init(timestamp: baseTime + 3, type: "keyDown", characters: "n", targetApp: "Google Chrome", targetURL: "https://mail.google.com"))
        events.append(.init(timestamp: baseTime + 4, type: "keyDown", characters: "v", targetApp: "Google Chrome", targetURL: "https://mail.google.com"))
        events.append(.init(timestamp: baseTime + 5, type: "keyDown", characters: "o", targetApp: "Google Chrome", targetURL: "https://mail.google.com"))
        events.append(.init(timestamp: baseTime + 6, type: "keyDown", characters: "i", targetApp: "Google Chrome", targetURL: "https://mail.google.com"))
        events.append(.init(timestamp: baseTime + 7, type: "keyDown", characters: "c", targetApp: "Google Chrome", targetURL: "https://mail.google.com"))
        events.append(.init(timestamp: baseTime + 8, type: "keyDown", characters: "e", targetApp: "Google Chrome", targetURL: "https://mail.google.com"))
        events.append(.init(timestamp: baseTime + 9, type: "keyDown", characters: "\r", targetApp: "Google Chrome", targetURL: "https://mail.google.com"))

        // Click on latest email, copy invoice number
        events.append(.init(timestamp: baseTime + 12, type: "mouseDown", position: ["x": 400, "y": 300], targetApp: "Google Chrome", targetURL: "https://mail.google.com"))
        events.append(.init(timestamp: baseTime + 14, type: "clipboardChange", targetApp: "Google Chrome", clipboardSnapshot: "INV-2024-0042"))

        // Open Google Sheets, paste invoice number
        events.append(.init(timestamp: baseTime + 18, type: "mouseMoved", position: ["x": 800, "y": 44], targetApp: "Google Chrome", targetURL: "https://docs.google.com/spreadsheets/d/abc123/edit"))
        events.append(.init(timestamp: baseTime + 20, type: "keyDown", characters: "I", targetApp: "Google Chrome", targetURL: "https://docs.google.com/spreadsheets/d/abc123/edit"))
        events.append(.init(timestamp: baseTime + 21, type: "keyDown", characters: "N", targetApp: "Google Chrome", targetURL: "https://docs.google.com/spreadsheets/d/abc123/edit"))
        events.append(.init(timestamp: baseTime + 22, type: "keyDown", characters: "V", modifiers: ["cmd"], targetApp: "Google Chrome", targetURL: "https://docs.google.com/spreadsheets/d/abc123/edit"))
        events.append(.init(timestamp: baseTime + 23, type: "keyDown", characters: "\t", targetApp: "Google Chrome", targetURL: "https://docs.google.com/spreadsheets/d/abc123/edit"))
        events.append(.init(timestamp: baseTime + 24, type: "keyDown", characters: "$", targetApp: "Google Chrome", targetURL: "https://docs.google.com/spreadsheets/d/abc123/edit"))
        events.append(.init(timestamp: baseTime + 25, type: "keyDown", characters: "1", targetApp: "Google Chrome", targetURL: "https://docs.google.com/spreadsheets/d/abc123/edit"))
        events.append(.init(timestamp: baseTime + 26, type: "keyDown", characters: ",", targetApp: "Google Chrome", targetURL: "https://docs.google.com/spreadsheets/d/abc123/edit"))
        events.append(.init(timestamp: baseTime + 27, type: "keyDown", characters: "2", targetApp: "Google Chrome", targetURL: "https://docs.google.com/spreadsheets/d/abc123/edit"))
        events.append(.init(timestamp: baseTime + 28, type: "keyDown", characters: "3", targetApp: "Google Chrome", targetURL: "https://docs.google.com/spreadsheets/d/abc123/edit"))
        events.append(.init(timestamp: baseTime + 29, type: "keyDown", characters: "4", targetApp: "Google Chrome", targetURL: "https://docs.google.com/spreadsheets/d/abc123/edit"))
        events.append(.init(timestamp: baseTime + 30, type: "keyDown", characters: ".", targetApp: "Google Chrome", targetURL: "https://docs.google.com/spreadsheets/d/abc123/edit"))
        events.append(.init(timestamp: baseTime + 31, type: "keyDown", characters: "5", targetApp: "Google Chrome", targetURL: "https://docs.google.com/spreadsheets/d/abc123/edit"))
        events.append(.init(timestamp: baseTime + 32, type: "keyDown", characters: "6", targetApp: "Google Chrome", targetURL: "https://docs.google.com/spreadsheets/d/abc123/edit"))

        return events
    }

    // MARK: - Sample Workflow 2: Lead Generation (LinkedIn → Sheets)

    static func sampleLeadWorkflow() -> [EventTapManager.CapturedEvent] {
        let baseTime: Double = 2000.0
        var events: [EventTapManager.CapturedEvent] = []

        events.append(.init(timestamp: baseTime + 0, type: "mouseMoved", position: ["x": 800, "y": 44], targetApp: "Google Chrome", targetURL: "https://linkedin.com/in/janedoe"))
        events.append(.init(timestamp: baseTime + 2, type: "mouseDown", position: ["x": 300, "y": 200], targetApp: "Google Chrome", targetURL: "https://linkedin.com/in/janedoe"))
        events.append(.init(timestamp: baseTime + 4, type: "clipboardChange", targetApp: "Google Chrome", clipboardSnapshot: "Name: Jane Doe\nTitle: VP Sales\nCompany: Acme Corp\nEmail: jane@acme.com"))

        events.append(.init(timestamp: baseTime + 8, type: "mouseMoved", position: ["x": 800, "y": 44], targetApp: "Google Chrome", targetURL: "https://docs.google.com/spreadsheets/d/xyz789/edit"))
        events.append(.init(timestamp: baseTime + 10, type: "keyDown", characters: "Jane Doe\tVP Sales\tAcme Corp\tjane@acme.com\r", targetApp: "Google Chrome", targetURL: "https://docs.google.com/spreadsheets/d/xyz789/edit"))

        return events
    }

    // MARK: - Sample Workflow 3: Simple Typing

    static func sampleTypingWorkflow() -> [EventTapManager.CapturedEvent] {
        let baseTime: Double = 3000.0
        var events: [EventTapManager.CapturedEvent] = []

        events.append(.init(timestamp: baseTime + 0, type: "mouseMoved", position: ["x": 100, "y": 200], targetApp: "Notes", targetURL: nil))
        events.append(.init(timestamp: baseTime + 1, type: "keyDown", characters: "H", targetApp: "Notes"))
        events.append(.init(timestamp: baseTime + 2, type: "keyDown", characters: "e", targetApp: "Notes"))
        events.append(.init(timestamp: baseTime + 3, type: "keyDown", characters: "l", targetApp: "Notes"))
        events.append(.init(timestamp: baseTime + 4, type: "keyDown", characters: "l", targetApp: "Notes"))
        events.append(.init(timestamp: baseTime + 5, type: "keyDown", characters: "o", targetApp: "Notes"))

        return events
    }

    // MARK: - Run All Tests

    struct TestResults: Codable {
        var testsRun: Int
        var testsPassed: Int
        var testsFailed: Int
        var results: [TestResult]

        struct TestResult: Codable {
            let name: String
            let passed: Bool
            let details: String
        }

        func summary() -> String {
            "\(testsPassed)/\(testsRun) passed, \(testsFailed) failed"
        }

        func toJSON() -> String {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            guard let data = try? encoder.encode(self),
                  let json = String(data: data, encoding: .utf8) else { return "{}" }
            return json
        }
    }

    static func runAll() -> TestResults {
        var results: [TestResults.TestResult] = []
        var passed = 0, failed = 0

        func test(_ name: String, _ fn: () -> Bool) {
            let ok = fn()
            if ok { passed += 1 } else { failed += 1 }
            results.append(.init(name: name, passed: ok, details: ok ? "PASS" : "FAIL"))
        }

        // Test 1: Semantic extraction produces actions from invoice workflow
        test("SemanticActionExtractor: invoice workflow") {
            let events = sampleInvoiceWorkflow()
            let actions = SemanticActionExtractor.extract(from: events)
            return !actions.isEmpty && actions.contains(where: { $0.action == "extract_data" || $0.action == "type_text" })
        }

        // Test 2: Intent inference detects invoice processing
        test("WorkflowIntentExtractor: invoice intent") {
            let events = sampleInvoiceWorkflow()
            let actions = SemanticActionExtractor.extract(from: events)
            let artifacts = WorkflowIntentExtractor.extractArtifacts(from: actions, events: events)
            let intent = WorkflowIntentExtractor.inferIntent(actions: actions, artifacts: artifacts)
            let ok = intent.domain == "accounts_payable" || intent.objective.contains("invoice")
            return ok
        }

        // Test 3: Graph builder produces connected graph
        test("WorkflowGraphBuilder: connected graph") {
            let events = sampleInvoiceWorkflow()
            let actions = SemanticActionExtractor.extract(from: events)
            let artifacts = WorkflowIntentExtractor.extractArtifacts(from: actions, events: events)
            let intent = WorkflowIntentExtractor.inferIntent(actions: actions, artifacts: artifacts)
            let graph = WorkflowGraphBuilder.buildFullGraph(from: actions, artifacts: artifacts, intent: intent, events: events)
            return graph.nodes.count > 0 && !graph.edges.isEmpty
        }

        // Test 4: Entity extraction finds entities
        test("EntityGraphBuilder: entities found") {
            let events = sampleInvoiceWorkflow()
            let actions = SemanticActionExtractor.extract(from: events)
            let artifacts = WorkflowIntentExtractor.extractArtifacts(from: actions, events: events)
            let intent = WorkflowIntentExtractor.inferIntent(actions: actions, artifacts: artifacts)
            let graph = WorkflowGraphBuilder.buildFullGraph(from: actions, artifacts: artifacts, intent: intent, events: events)
            let entityGraph = EntityGraphBuilder.build(events: events, actions: actions, artifacts: artifacts, graph: graph)
            return !entityGraph.entities.isEmpty || !entityGraph.fieldMappings.isEmpty
        }

        // Test 5: BeliefState initializes and updates
        test("BeliefStateEngine: init and update") {
            let events = sampleInvoiceWorkflow()
            let actions = SemanticActionExtractor.extract(from: events)
            let artifacts = WorkflowIntentExtractor.extractArtifacts(from: actions, events: events)
            var state = BeliefStateEngine.initialize(sessionId: "test1")
            BeliefStateEngine.update(&state, events: events, partialActions: actions, partialArtifacts: artifacts)
            return state.version > 0 && !state.intentDistribution.coreIntentDistribution.isEmpty
        }

        // Test 6: BeliefState snapshot is valid
        test("BeliefStateEngine: snapshot") {
            let events = sampleInvoiceWorkflow()
            let actions = SemanticActionExtractor.extract(from: events)
            let artifacts = WorkflowIntentExtractor.extractArtifacts(from: actions, events: events)
            var state = BeliefStateEngine.initialize(sessionId: "test2")
            BeliefStateEngine.update(&state, events: events, partialActions: actions, partialArtifacts: artifacts)
            let snap = BeliefStateEngine.snapshot(from: state)
            return snap.version > 0 && snap.readiness == "uncertain" || snap.readiness == "ready"
        }

        // Test 7: Evaluation engine produces DebugBundle
        test("WorkflowEvaluationEngine: debug bundle") {
            let events = sampleInvoiceWorkflow()
            let actions = SemanticActionExtractor.extract(from: events)
            let artifacts = WorkflowIntentExtractor.extractArtifacts(from: actions, events: events)
            let intent = WorkflowIntentExtractor.inferIntent(actions: actions, artifacts: artifacts)
            let graph = WorkflowGraphBuilder.buildFullGraph(from: actions, artifacts: artifacts, intent: intent, events: events)
            let entityGraph = EntityGraphBuilder.build(events: events, actions: actions, artifacts: artifacts, graph: graph)
            let bundle = WorkflowEvaluationEngine.evaluateWorkflow(
                sessionId: "test3", events: events, actions: actions,
                intent: intent, graph: graph, entityGraph: entityGraph
            )
            return !bundle.groundTruth.id.isEmpty
        }

        // Test 8: Policy engine selects strategy
        test("OutcomePolicyEngine: strategy selection") {
            let events = sampleInvoiceWorkflow()
            let actions = SemanticActionExtractor.extract(from: events)
            let context = OutcomePolicyEngine.extractContext(from: actions, events: events)
            let table = StrategyScoreTable(entries: [:], lastCompactionAt: Date(), totalEvaluations: 0, averageReward: 0)
            let strategy = OutcomePolicyEngine.selectStrategy(for: context, from: table)
            return strategy.fingerprint.count > 0
        }

        // Test 9: Full pipeline runs end-to-end
        test("MirrorPipeline: end-to-end") {
            let events = sampleInvoiceWorkflow()
            let output = MirrorPipeline.analyze(sessionId: "pipeline_test", events: events)
            return output.semanticActions.count > 0 &&
                   output.workflowGraph.nodes.count > 0 &&
                   !output.beliefStateSnapshot.readiness.isEmpty
        }

        // Test 10: Lead workflow extracts correctly
        test("SemanticActionExtractor: lead workflow") {
            let events = sampleLeadWorkflow()
            let actions = SemanticActionExtractor.extract(from: events)
            let artifacts = WorkflowIntentExtractor.extractArtifacts(from: actions, events: events)
            let intent = WorkflowIntentExtractor.inferIntent(actions: actions, artifacts: artifacts)
            return intent.domain == "lead_generation" || intent.objective.contains("lead") || !actions.isEmpty
        }

        return TestResults(testsRun: results.count, testsPassed: passed, testsFailed: failed, results: results)
    }
}
