import Foundation
import Testing
@testable import NotchivityKit

private func config(_ directory: String, isDefault: Bool = false,
                    id: String? = "uuid-1", email: String? = "wesley@idexx.com") -> ClaudeAccountDiscovery.Config {
    var oauth: [String: Any] = [:]
    if let id { oauth["accountUuid"] = id }
    if let email { oauth["emailAddress"] = email }
    let json = try! JSONSerialization.data(withJSONObject: ["oauthAccount": oauth])
    return .init(directory: directory, isDefault: isDefault, json: json)
}

@Suite struct ClaudeAccountTests {
    @Test func defaultDirectoryUsesBareKeychainService() {
        #expect(ClaudeAccount.keychainService(forConfigDirectory: "/Users/w/.claude", isDefault: true)
                == "Claude Code-credentials")
    }

    @Test func customDirectoryAppendsSHA256PrefixOfItsPath() {
        // Observed on a real machine: this is the item Claude Code created for that directory.
        #expect(ClaudeAccount.keychainService(forConfigDirectory: "/Users/wcoetzee/.claude-account2", isDefault: false)
                == "Claude Code-credentials-af4ff2ea")
    }

    @Test func labelIsEmailDomainWithoutTLD() {
        #expect(ClaudeAccount.label(forEmail: "wesley.coetzee@ezyvet.com", fallback: "x") == "ezyvet")
        #expect(ClaudeAccount.label(forEmail: nil, fallback: ".claude-account2") == ".claude-account2")
    }

    @Test func discoveryKeepsOrderAndDropsRepeatSignIns() {
        let accounts = ClaudeAccountDiscovery.accounts(from: [
            config("/h/.claude", isDefault: true, id: "one"),
            config("/h/.claude-work", id: "two", email: "w@ezyvet.com"),
            config("/h/.claude-again", id: "one"),
        ])

        #expect(accounts.map(\.id) == ["one", "two"])
        #expect(accounts.map(\.label) == ["idexx", "ezyvet"])
        #expect(accounts[0].keychainService == "Claude Code-credentials")
        #expect(accounts[1].keychainService.hasPrefix("Claude Code-credentials-"))
    }

    @Test func discoverySkipsDirectoriesWithoutASignIn() {
        let accounts = ClaudeAccountDiscovery.accounts(from: [
            config("/h/.claude", isDefault: true, id: nil),
            .init(directory: "/h/.claude-empty", isDefault: false, json: nil),
            config("/h/.claude-ok", id: "two"),
        ])

        #expect(accounts.map(\.id) == ["two"])
    }
}
