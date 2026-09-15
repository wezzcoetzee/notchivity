import CryptoKit
import Foundation

/// One Claude Code sign-in the poller can read usage for.
///
/// Claude Code keeps one config directory per sign-in: `~/.claude` by default, or whatever
/// `CLAUDE_CONFIG_DIR` points at. Each directory's OAuth token lives in its own Keychain
/// item: the default directory uses the bare `Claude Code-credentials` service name, and
/// every other directory gets that name suffixed with the first 8 hex digits of the
/// SHA-256 of its absolute path.
public struct ClaudeAccount: Equatable {
    public let id: String
    public let label: String
    public let keychainService: String

    public init(id: String, label: String, keychainService: String) {
        self.id = id
        self.label = label
        self.keychainService = keychainService
    }

    public static let keychainServicePrefix = "Claude Code-credentials"

    public static func keychainService(forConfigDirectory path: String, isDefault: Bool) -> String {
        guard !isDefault else { return keychainServicePrefix }
        let digest = SHA256.hash(data: Data(path.utf8))
        let hash = digest.map { String(format: "%02x", $0) }.joined().prefix(8)
        return "\(keychainServicePrefix)-\(hash)"
    }

    /// The short name shown next to each account: the email's domain without its
    /// TLD (`wesley@idexx.com` → `idexx`), falling back to the config directory's name.
    public static func label(forEmail email: String?, fallback: String) -> String {
        guard let domain = email?.split(separator: "@").last,
              let name = domain.split(separator: ".").first else { return fallback }
        return String(name)
    }
}

public enum ClaudeAccountDiscovery {
    public static let defaultDirectoryName = ".claude"
    static let configFileName = ".claude.json"

    public struct Config {
        public let directory: String
        public let isDefault: Bool
        public let json: Data?

        public init(directory: String, isDefault: Bool, json: Data?) {
            self.directory = directory
            self.isDefault = isDefault
            self.json = json
        }
    }

    /// The default sign-in first, then every `~/.claude-*` sibling directory in name order.
    /// The default directory's config file sits beside it at `~/.claude.json`; a custom
    /// directory keeps its config file inside itself.
    public static func discover(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [ClaudeAccount] {
        let fileManager = FileManager.default
        var configs = [Config(directory: home.appendingPathComponent(defaultDirectoryName).path,
                              isDefault: true,
                              json: try? Data(contentsOf: home.appendingPathComponent(configFileName)))]
        let siblings = ((try? fileManager.contentsOfDirectory(at: home, includingPropertiesForKeys: [.isDirectoryKey])) ?? [])
            .filter { $0.lastPathComponent.hasPrefix(defaultDirectoryName + "-") }
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for directory in siblings {
            configs.append(Config(directory: directory.path, isDefault: false,
                                  json: try? Data(contentsOf: directory.appendingPathComponent(configFileName))))
        }
        return accounts(from: configs)
    }

    /// Keeps input order and drops repeat sign-ins of the same account (the same login can
    /// be reached through more than one config directory).
    public static func accounts(from configs: [Config]) -> [ClaudeAccount] {
        var seen = Set<String>()
        return configs.compactMap(account(from:)).filter { seen.insert($0.id).inserted }
    }

    static func account(from config: Config) -> ClaudeAccount? {
        guard let json = config.json,
              let root = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any],
              let oauth = root["oauthAccount"] as? [String: Any],
              let id = oauth["accountUuid"] as? String else { return nil }
        let fallback = URL(fileURLWithPath: config.directory).lastPathComponent
        return ClaudeAccount(
            id: id,
            label: ClaudeAccount.label(forEmail: oauth["emailAddress"] as? String, fallback: fallback),
            keychainService: ClaudeAccount.keychainService(forConfigDirectory: config.directory,
                                                           isDefault: config.isDefault))
    }
}
