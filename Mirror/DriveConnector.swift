import Foundation

class DriveConnector {

    private let driveAPIBase = "https://www.googleapis.com/drive/v3"
    private let uploadBase = "https://www.googleapis.com/upload/drive/v3"
    private let oauthManager = GoogleOAuthManager()

    func uploadFile(filePath: String, mimeType: String = "application/octet-stream", folderId: String? = nil) async throws -> String {
        let accessToken = try await oauthManager.getValidAccessToken()
        let fileURL = URL(fileURLWithPath: filePath)
        let fileData = try Data(contentsOf: fileURL)
        let filename = fileURL.lastPathComponent

        guard let url = URL(string: "\(uploadBase)/files?uploadType=multipart") else {
            throw ConnectorError.apiError("Invalid Drive upload URL")
        }

        var metadata: [String: Any] = ["name": filename]
        if let folder = folderId { metadata["parents"] = [folder] }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
        body.append(try JSONSerialization.data(withJSONObject: metadata))
        body.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let fileId = json["id"] as? String else {
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            throw ConnectorError.apiError("Drive upload failed: \(bodyStr)")
        }
        return fileId
    }

    func downloadFile(fileId: String, destinationDir: String) async throws -> String {
        let accessToken = try await oauthManager.getValidAccessToken()

        guard let metaURL = URL(string: "\(driveAPIBase)/files/\(fileId)?fields=name") else {
            throw ConnectorError.apiError("Invalid Drive metadata URL")
        }
        var metaRequest = URLRequest(url: metaURL)
        metaRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (metaData, _) = try await URLSession.shared.data(for: metaRequest)
        let filename = (try? JSONSerialization.jsonObject(with: metaData) as? [String: Any])?["name"] as? String ?? "downloaded_file"

        guard let downloadURL = URL(string: "\(driveAPIBase)/files/\(fileId)?alt=media") else {
            throw ConnectorError.apiError("Invalid Drive download URL")
        }
        var request = URLRequest(url: downloadURL)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (fileData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ConnectorError.apiError("Drive download failed")
        }

        let destURL = URL(fileURLWithPath: destinationDir).appendingPathComponent(filename)
        try FileManager.default.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileData.write(to: destURL)
        return destURL.path
    }

    func searchFiles(query: String, maxResults: Int = 10) async throws -> [DriveFile] {
        let accessToken = try await oauthManager.getValidAccessToken()

        guard var components = URLComponents(string: "\(driveAPIBase)/files") else {
            throw ConnectorError.apiError("Invalid Drive search URL")
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "pageSize", value: String(maxResults)),
            URLQueryItem(name: "fields", value: "files(id,name,mimeType,size,createdTime,webViewLink)")
        ]
        guard let url = components.url else {
            throw ConnectorError.apiError("Invalid Drive search URL components")
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let files = json["files"] as? [[String: Any]] else {
            return []
        }

        return files.compactMap { file in
            DriveFile(
                id: file["id"] as? String ?? "",
                name: file["name"] as? String ?? "",
                mimeType: file["mimeType"] as? String ?? "",
                size: file["size"] as? String,
                createdTime: file["createdTime"] as? String ?? "",
                webViewLink: file["webViewLink"] as? String ?? ""
            )
        }
    }

    func shareFile(fileId: String, role: String = "reader") async throws -> String {
        let accessToken = try await oauthManager.getValidAccessToken()

        guard let url = URL(string: "\(driveAPIBase)/files/\(fileId)/permissions") else {
            throw ConnectorError.apiError("Invalid Drive permissions URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["role": role, "type": "anyone"])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["id"] != nil else {
            throw ConnectorError.apiError("Drive share failed")
        }
        return "https://drive.google.com/file/d/\(fileId)/view"
    }

    enum ConnectorError: Error, LocalizedError {
        case apiError(String)
        var errorDescription: String? {
            switch self { case .apiError(let msg): return msg }
        }
    }
}

struct DriveFile: Codable {
    let id: String
    let name: String
    let mimeType: String
    let size: String?
    let createdTime: String
    let webViewLink: String
}
