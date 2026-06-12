import Foundation

// MARK: - Slack Connector

class SlackConnector {

    private let slackAPIBase = "https://slack.com/api"

    /// Post a message to a Slack channel. Requires `chat:write` scope.
    func postMessage(channel: String, text: String, threadTs: String? = nil) async throws {
        guard let token = CredentialStore.shared.get(key: "slack_access_token") else {
            throw ConnectorError.notAuthenticated
        }

        var request = URLRequest(url: URL(string: "\(slackAPIBase)/chat.postMessage")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = ["channel": channel, "text": text]
        if let thread = threadTs { body["thread_ts"] = thread }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["ok"] as? Bool == true else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ConnectorError.apiError("Slack postMessage failed: \(body)")
        }
    }

    /// Upload a file to a Slack channel. Requires `files:write` scope.
    func uploadFile(channel: String, filePath: String, title: String? = nil, initialComment: String? = nil) async throws {
        guard let token = CredentialStore.shared.get(key: "slack_access_token") else {
            throw ConnectorError.notAuthenticated
        }

        let fileURL = URL(fileURLWithPath: filePath)
        let fileData = try Data(contentsOf: fileURL)
        let boundary = "Boundary-\(UUID().uuidString)"
        let filename = fileURL.lastPathComponent

        var request = URLRequest(url: URL(string: "\(slackAPIBase)/files.upload")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func appendField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        appendField("channels", channel)
        if let title = title { appendField("title", title) }
        if let comment = initialComment { appendField("initial_comment", comment) }

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["ok"] as? Bool == true else {
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            throw ConnectorError.apiError("Slack uploadFile failed: \(bodyStr)")
        }
    }

    /// List recent messages from a channel. Requires `channels:history` scope.
    func fetchMessages(channel: String, limit: Int = 10) async throws -> [SlackMessage] {
        guard let token = CredentialStore.shared.get(key: "slack_access_token") else {
            throw ConnectorError.notAuthenticated
        }

        var components = URLComponents(string: "\(slackAPIBase)/conversations.history")!
        components.queryItems = [
            URLQueryItem(name: "channel", value: channel),
            URLQueryItem(name: "limit", value: String(limit))
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["ok"] as? Bool == true,
              let messages = json["messages"] as? [[String: Any]] else {
            return []
        }

        return messages.compactMap { msg in
            SlackMessage(
                ts: msg["ts"] as? String ?? "",
                user: msg["user"] as? String ?? "",
                text: msg["text"] as? String ?? "",
                threadTs: msg["thread_ts"] as? String
            )
        }
    }

    enum ConnectorError: Error, LocalizedError {
        case notAuthenticated
        case apiError(String)
        var errorDescription: String? {
            switch self {
            case .notAuthenticated: return "Slack not connected. Add token in Settings → Integrations."
            case .apiError(let msg): return "Slack API error: \(msg)"
            }
        }
    }
}

struct SlackMessage: Codable {
    let ts: String
    let user: String
    let text: String
    let threadTs: String?
}
