import NotchivityKit
import SwiftUI

struct CLIProxyConnectionView: View {
    let onSaved: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var url = Config.load().cliProxyURL ?? ""
    @State private var token = ""
    @State private var tokenLoaded = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("CLI proxy").font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                Text("Base URL")
                TextField("https://proxy.example.com", text: $url)
                    .textFieldStyle(.plain).padding(8)
                    .overlay(Rectangle().stroke(Color.stroke))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Read-only token")
                SecureField("USAGE_LIMITS_TOKEN", text: $token)
                    .textFieldStyle(.plain).padding(8)
                    .overlay(Rectangle().stroke(Color.stroke))
            }
            Text("Stored in Keychain. Clear the URL for local discovery.")
                .font(.detail).foregroundStyle(Color.dim)
            if let error { Text(error).font(.detail).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save", action: save).keyboardShortcut(.defaultAction).disabled(!tokenLoaded)
            }
        }
        .padding(20)
        .frame(width: 460)
        .background(.black)
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .task {
            do {
                token = try CLIProxyToken.load()
                tokenLoaded = true
            } catch { self.error = (error as? UsageError)?.description ?? "Could not read the CLI proxy token" }
        }
    }

    private func save() {
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if !trimmedURL.isEmpty {
                _ = try CLIProxyUsageSource.endpoint(for: trimmedURL)
                guard !trimmedToken.isEmpty else { throw UsageError.other("Enter the proxy's read-only USAGE_LIMITS_TOKEN") }
            }
            var config = Config.load()
            config.cliProxyURL = trimmedURL.isEmpty ? nil : trimmedURL
            let previousToken = try CLIProxyToken.load()
            try CLIProxyToken.save(trimmedURL.isEmpty ? "" : trimmedToken)
            do { try config.save() } catch {
                try CLIProxyToken.save(previousToken)
                throw error
            }
            onSaved(trimmedURL)
            dismiss()
        } catch { self.error = (error as? UsageError)?.description ?? "Could not save the CLI proxy connection" }
    }
}
