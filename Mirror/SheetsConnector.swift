import Foundation

class SheetsConnector {

    private let oauthManager = GoogleOAuthManager()

    func appendRow(spreadsheetId: String, range: String, values: [String]) async throws {
        let accessToken = try await oauthManager.getValidAccessToken()

        let encodedRange = range.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? range
        let urlString = "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetId)/values/\(encodedRange):append?valueInputOption=USER_ENTERED"

        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "values": [values]
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ConnectorError.apiError("Sheets append failed: \(body)")
        }
    }

    func readRange(spreadsheetId: String, range: String) async throws -> [[String]] {
        let accessToken = try await oauthManager.getValidAccessToken()

        let encodedRange = range.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? range
        let urlString = "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetId)/values/\(encodedRange)"

        var request = URLRequest(url: URL(string: urlString)!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let values = json["values"] as? [[Any]] else {
            return []
        }

        return values.map { row in row.map { "\($0)" } }
    }

    func createSheet(title: String) async throws -> String {
        let accessToken = try await oauthManager.getValidAccessToken()

        var request = URLRequest(url: URL(string: "https://sheets.googleapis.com/v4/spreadsheets")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "properties": ["title": title]
        ])

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let spreadsheetId = json["spreadsheetId"] as? String else {
            throw ConnectorError.apiError("Sheet creation failed")
        }
        return spreadsheetId
    }

    static func extractSpreadsheetId(from url: String) -> String? {
        guard let range = url.range(of: "/d/") else { return nil }
        let afterD = url[range.upperBound...]
        return afterD.split(separator: "/").first.map(String.init)
    }

    enum ConnectorError: Error, LocalizedError {
        case apiError(String)
        var errorDescription: String? {
            switch self { case .apiError(let msg): return msg }
        }
    }
}
