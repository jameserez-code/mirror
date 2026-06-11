import Foundation

class HistoryStore {
    private let fileName = "run_history.json"
    private var entries: [WorkflowEngine.RunLogEntry] = []

    init() {
        load()
    }

    func append(entry: WorkflowEngine.RunLogEntry) {
        entries.insert(entry, at: 0)
        if entries.count > 500 { entries = Array(entries.prefix(500)) }
        save()
    }

    func allEntries() -> [WorkflowEngine.RunLogEntry] {
        return entries
    }

    func entriesForWorkflow(id: String) -> [WorkflowEngine.RunLogEntry] {
        return entries.filter { $0.workflowId == id }
    }

    func recentEntries(limit: Int = 20) -> [WorkflowEngine.RunLogEntry] {
        return Array(entries.prefix(limit))
    }

    // MARK: - Persistence

    private var storageURL: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Mirror/Data")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        let decoder = JSONDecoder()
        entries = (try? decoder.decode([WorkflowEngine.RunLogEntry].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(entries) {
            try? data.write(to: storageURL)
        }
    }
}
