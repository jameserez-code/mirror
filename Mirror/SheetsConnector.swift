import Foundation

class SheetsConnector {

    private let oauthManager = GoogleOAuthManager()

    func appendRow(spreadsheetId: String, range: String, values: [String]) async throws {
        let accessToken = try await oauthManager.getValidAccessToken()

        let encodedRange = range.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? range
        guard let url = URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetId)/values/\(encodedRange):append?valueInputOption=USER_ENTERED") else {
            throw ConnectorError.apiError("Invalid Sheets API URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["values": [values]])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ConnectorError.apiError("No HTTP response from Sheets")
        }
        if http.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? ""
            print("[Mirror Sheets] Append failed: HTTP \(http.statusCode) — \(body)")
            throw ConnectorError.apiError("Sheets append failed (HTTP \(http.statusCode))")
        }
    }

    func readRange(spreadsheetId: String, range: String) async throws -> [[String]] {
        let accessToken = try await oauthManager.getValidAccessToken()

        let encodedRange = range.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? range
        guard let url = URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetId)/values/\(encodedRange)") else {
            throw ConnectorError.apiError("Invalid Sheets read URL")
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ConnectorError.apiError("No HTTP response from Sheets read")
        }
        if http.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? ""
            print("[Mirror Sheets] Read failed: HTTP \(http.statusCode) — \(body)")
            throw ConnectorError.apiError("Sheets read failed (HTTP \(http.statusCode))")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let values = json["values"] as? [[Any]] else {
            return []
        }

        return values.map { row in row.map { "\($0)" } }
    }

    func createSheet(title: String) async throws -> String {
        let accessToken = try await oauthManager.getValidAccessToken()

        guard let url = URL(string: "https://sheets.googleapis.com/v4/spreadsheets") else {
            throw ConnectorError.apiError("Invalid Sheets create URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "properties": ["title": title]
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ConnectorError.apiError("No HTTP response from Sheets create")
        }
        if http.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? ""
            print("[Mirror Sheets] Create failed: HTTP \(http.statusCode) — \(body)")
            throw ConnectorError.apiError("Sheet creation failed (HTTP \(http.statusCode))")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let spreadsheetId = json["spreadsheetId"] as? String else {
            throw ConnectorError.apiError("Sheet creation response missing spreadsheetId")
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
