import Foundation
import AppKit
import CryptoKit

class GoogleOAuthManager {

    private let scopes = [
        "https://www.googleapis.com/auth/gmail.send",
        "https://www.googleapis.com/auth/gmail.readonly",
        "https://www.googleapis.com/auth/spreadsheets"
    ]

    private var codeVerifier: String = ""
    private var listener: LocalCallbackServer?

    // MARK: - Start OAuth Flow

    func startAuthFlow(completion: @escaping (Result<Void, Error>) -> Void) {
        codeVerifier = generateCodeVerifier()
        let codeChallenge = generateCodeChallenge(from: codeVerifier)

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: GoogleOAuthConfig.clientId),
            URLQueryItem(name: "redirect_uri", value: GoogleOAuthConfig.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]

        guard let authURL = components.url else {
            completion(.failure(OAuthError.invalidURL))
            return
        }

        listener = LocalCallbackServer(port: 8765)
        listener?.onCallback = { [weak self] code in
            self?.exchangeCodeForTokens(code: code, completion: completion)
        }
        listener?.onError = { error in
            completion(.failure(error))
        }

        do {
            try listener?.start()
        } catch {
            completion(.failure(error))
            return
        }

        NSWorkspace.shared.open(authURL)
    }

    // MARK: - Token Exchange

    private func exchangeCodeForTokens(code: String, completion: @escaping (Result<Void, Error>) -> Void) {
        listener?.stop()

        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params = [
            "client_id": GoogleOAuthConfig.clientId,
            "client_secret": GoogleOAuthConfig.clientSecret,
            "code": code,
            "code_verifier": codeVerifier,
            "grant_type": "authorization_code",
            "redirect_uri": GoogleOAuthConfig.redirectURI
        ]
        request.httpBody = params.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        let session = URLSession(configuration: config)

        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(.failure(OAuthError.invalidResponse))
                return
            }

            if let accessToken = json["access_token"] as? String,
               let refreshToken = json["refresh_token"] as? String,
               let expiresIn = json["expires_in"] as? Int {

                let expiryDate = Date().addingTimeInterval(TimeInterval(expiresIn))
                CredentialStore.shared.save(key: "google_access_token", value: accessToken)
                CredentialStore.shared.save(key: "google_refresh_token", value: refreshToken)
                CredentialStore.shared.save(key: "google_token_expiry", value: ISO8601DateFormatter().string(from: expiryDate))

                DispatchQueue.main.async { completion(.success(())) }
            } else {
                completion(.failure(OAuthError.tokenExchangeFailed))
            }
        }.resume()
    }

    // MARK: - Token Refresh

    func getValidAccessToken() async throws -> String {
        guard let accessToken = CredentialStore.shared.get(key: "google_access_token"),
              let refreshToken = CredentialStore.shared.get(key: "google_refresh_token"),
              let expiryString = CredentialStore.shared.get(key: "google_token_expiry"),
              let expiryDate = ISO8601DateFormatter().date(from: expiryString) else {
            throw OAuthError.notAuthenticated
        }

        if expiryDate.timeIntervalSinceNow > 60 {
            return accessToken
        }

        return try await refreshAccessToken(refreshToken: refreshToken)
    }

    private func refreshAccessToken(refreshToken: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params = [
            "client_id": GoogleOAuthConfig.clientId,
            "client_secret": GoogleOAuthConfig.clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        request.httpBody = params.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String,
              let expiresIn = json["expires_in"] as? Int else {
            throw OAuthError.tokenRefreshFailed
        }

        let expiryDate = Date().addingTimeInterval(TimeInterval(expiresIn))
        CredentialStore.shared.save(key: "google_access_token", value: accessToken)
        CredentialStore.shared.save(key: "google_token_expiry", value: ISO8601DateFormatter().string(from: expiryDate))

        return accessToken
    }

    // MARK: - Connection Status

    static func isConnected() -> Bool {
        return CredentialStore.shared.get(key: "google_refresh_token") != nil
    }

    static func disconnect() {
        CredentialStore.shared.delete(key: "google_access_token")
        CredentialStore.shared.delete(key: "google_refresh_token")
        CredentialStore.shared.delete(key: "google_token_expiry")
    }

    // MARK: - PKCE Helpers

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hashed = SHA256.hash(data: data)
        return Data(hashed).base64URLEncodedString()
    }

    enum OAuthError: Error, LocalizedError {
        case invalidURL, invalidResponse, tokenExchangeFailed, tokenRefreshFailed, notAuthenticated
        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid OAuth URL"
            case .invalidResponse: return "Invalid OAuth response"
            case .tokenExchangeFailed: return "Failed to exchange code for tokens"
            case .tokenRefreshFailed: return "Failed to refresh access token"
            case .notAuthenticated: return "Google account not connected"
            }
        }
    }
}

// MARK: - Base64URL Encoding

extension Data {
    func base64URLEncodedString() -> String {
        return base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Local Callback Server

class LocalCallbackServer {
    private let port: UInt16
    var onCallback: ((String) -> Void)?
    var onError: ((Error) -> Void)?

    init(port: UInt16) {
        self.port = port
    }

    func start() throws {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else {
            throw NSError(domain: "Mirror", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create socket"])
        }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            close(sock)
            throw NSError(domain: "Mirror", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not bind port \(port)"])
        }

        listen(sock, 1)

        DispatchQueue.global().async { [weak self] in
            let client = accept(sock, nil, nil)
            guard client >= 0 else { close(sock); return }

            var buffer = [UInt8](repeating: 0, count: 4096)
            let bytesRead = recv(client, &buffer, buffer.count, 0)
            guard bytesRead > 0 else { close(client); close(sock); return }

            let request = String(decoding: buffer[0..<Int(bytesRead)], as: UTF8.self)

            var code = ""
            if let codeRange = request.range(of: "code=") {
                let after = request[codeRange.upperBound...]
                code = after.split(separator: "&").first.map(String.init)
                    ?? after.split(separator: " ").first.map(String.init)
                    ?? ""
            }

            let response = """
            HTTP/1.1 200 OK\r
            Content-Type: text/html\r
            Connection: close\r
            \r
            <html><body style="font-family:-apple-system;text-align:center;padding-top:100px;background:#111;color:#fff;">
            <h2>Mirror connected to Google</h2>
            <p>You can close this window and return to Mirror.</p>
            </body></html>
            """
            _ = response.withCString { send(client, $0, strlen($0), 0) }
            close(client)
            close(sock)

            if !code.isEmpty {
                DispatchQueue.main.async { self?.onCallback?(code) }
            }
        }
    }

    func stop() {}
}
