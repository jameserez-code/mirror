import Foundation

struct Settings {
    static let defaults = UserDefaults.standard

    enum Key: String {
        case userName
        case apiProvider    // "openrouter", "anthropic", or "openai"
        case anthropicKey   // stored in Keychain; UserDefaults holds presence marker
        case openaiKey      // stored in Keychain; UserDefaults holds presence marker
        case openRouterKey  // stored in Keychain; UserDefaults holds presence marker
        case openRouterModel
        case firebaseEnabled
        case hasLaunchedBefore
        case lastSessionId
        case autoAnalyze    // auto-trigger analysis after recording stops
    }

    static var userName: String {
        get { defaults.string(forKey: Key.userName.rawValue) ?? "" }
        set { defaults.set(newValue, forKey: Key.userName.rawValue) }
    }

    static var apiProvider: String {
        get { defaults.string(forKey: Key.apiProvider.rawValue) ?? "openrouter" }
        set { defaults.set(newValue, forKey: Key.apiProvider.rawValue) }
    }

    static var openRouterKeySet: Bool {
        defaults.bool(forKey: Key.openRouterKey.rawValue)
    }

    static var anthropicKeySet: Bool {
        defaults.bool(forKey: Key.anthropicKey.rawValue)
    }

    static var openaiKeySet: Bool {
        defaults.bool(forKey: Key.openaiKey.rawValue)
    }

    static var openRouterModel: String {
        get { defaults.string(forKey: Key.openRouterModel.rawValue) ?? "anthropic/claude-3.5-haiku" }
        set { defaults.set(newValue, forKey: Key.openRouterModel.rawValue) }
    }

    static var firebaseEnabled: Bool {
        get { defaults.bool(forKey: Key.firebaseEnabled.rawValue) }
        set { defaults.set(newValue, forKey: Key.firebaseEnabled.rawValue) }
    }

    static var hasLaunchedBefore: Bool {
        get { defaults.bool(forKey: Key.hasLaunchedBefore.rawValue) }
        set { defaults.set(newValue, forKey: Key.hasLaunchedBefore.rawValue) }
    }

    static var autoAnalyze: Bool {
        get {
            if defaults.object(forKey: Key.autoAnalyze.rawValue) == nil { return true }
            return defaults.bool(forKey: Key.autoAnalyze.rawValue)
        }
        set { defaults.set(newValue, forKey: Key.autoAnalyze.rawValue) }
    }

    static func markAPIKeySet(provider: String) {
        switch provider {
        case "anthropic": defaults.set(true, forKey: Key.anthropicKey.rawValue)
        case "openai": defaults.set(true, forKey: Key.openaiKey.rawValue)
        case "openrouter": defaults.set(true, forKey: Key.openRouterKey.rawValue)
        default: break
        }
    }

    static func clearAPIKey(provider: String) {
        switch provider {
        case "anthropic": defaults.set(false, forKey: Key.anthropicKey.rawValue)
        case "openai": defaults.set(false, forKey: Key.openaiKey.rawValue)
        case "openrouter": defaults.set(false, forKey: Key.openRouterKey.rawValue)
        default: break
        }
    }

    static func loadHTML(_ name: String) -> String {
        if let url = Bundle.main.url(forResource: name, withExtension: "html") {
            return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }
        if let url = Bundle.module.url(forResource: name, withExtension: "html") {
            return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }
        return ""
    }
}
