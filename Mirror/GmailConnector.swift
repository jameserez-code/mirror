import Foundation

class GmailConnector {

    private let oauthManager = GoogleOAuthManager()

    func send(to: String, subject: String, body: String) async throws {
        let accessToken = try await oauthManager.getValidAccessToken()

        let message = """
        To: \(to)\r
        Subject: \(subject)\r
        Content-Type: text/plain; charset="UTF-8"\r
        \r
        \(body)
        """

        let rawMessage = Data(message.utf8).base64URLEncodedString()

        guard let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/send") else {
            throw ConnectorError.apiError("Invalid Gmail API URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["raw": rawMessage])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ConnectorError.apiError("No HTTP response")
        }
        if http.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? ""
            print("[Mirror Gmail] Send failed: HTTP \(http.statusCode) — \(body)")
            throw ConnectorError.apiError("Gmail send failed (HTTP \(http.statusCode))")
        }
    }

    func search(query: String, maxResults: Int = 10) async throws -> [GmailMessage] {
        let accessToken = try await oauthManager.getValidAccessToken()

        guard var components = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages") else {
            throw ConnectorError.apiError("Invalid Gmail API URL")
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "maxResults", value: String(maxResults))
        ]

        guard let url = components.url else {
            throw ConnectorError.apiError("Invalid Gmail search URL")
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ConnectorError.apiError("No HTTP response from Gmail search")
        }
        if http.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? ""
            print("[Mirror Gmail] Search failed: HTTP \(http.statusCode) — \(body)")
            throw ConnectorError.apiError("Gmail search failed (HTTP \(http.statusCode))")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messages = json["messages"] as? [[String: Any]] else {
            return []
        }

        var results: [GmailMessage] = []
        for msg in messages {
            guard let id = msg["id"] as? String else { continue }
            if let detail = try await fetchMessage(id: id, accessToken: accessToken) {
                results.append(detail)
            }
        }
        return results
    }

    private func fetchMessage(id: String, accessToken: String) async throws -> GmailMessage? {
        let encodedId = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        guard let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(encodedId)?format=metadata&metadataHeaders=Subject&metadataHeaders=From") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return nil }
        if http.statusCode != 200 {
            print("[Mirror Gmail] Fetch message \(id) failed: HTTP \(http.statusCode)")
            return nil
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = json["payload"] as? [String: Any],
              let headers = payload["headers"] as? [[String: Any]] else {
            return nil
        }

        var subject = "", from = ""
        for header in headers {
            if let name = header["name"] as? String, let value = header["value"] as? String {
                if name == "Subject" { subject = value }
                if name == "From" { from = value }
            }
        }

        return GmailMessage(
            id: id,
            from: from,
            subject: subject,
            snippet: json["snippet"] as? String ?? ""
        )
    }

    enum ConnectorError: Error, LocalizedError {
        case apiError(String)
        var errorDescription: String? {
            switch self { case .apiError(let msg): return msg }
        }
    }
}

struct GmailMessage: Codable {
    let id: String
    let from: String
    let subject: String
    let snippet: String
}
