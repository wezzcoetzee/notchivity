import Foundation

/// Connection settings in JSON. The CLI proxy token lives separately in Keychain.
/// `~/.config/notchivity/config.json`: `{ "slackChannel": "C…", "slackBotToken": "xoxb-…" }`.
public struct Config: Codable {
    public var slackChannel: String?
    public var slackBotToken: String?
    public var cliProxyURL: String?

    public var usesCLIProxy: Bool {
        !(cliProxyURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/notchivity", isDirectory: true)
    public static let file = directory.appendingPathComponent("config.json")

    public static func load() -> Config {
        guard let data = try? Data(contentsOf: file),
            let config = try? JSONDecoder().decode(Config.self, from: data)
        else { return Config() }
        return config
    }

    public var slackConfigured: Bool { !(slackChannel ?? "").isEmpty }

    public func save() throws {
        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: Self.file, options: .atomic)
    }
}
