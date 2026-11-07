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
            Text("CLI proxy").font(.bodyStrong)
            labelled("Base URL") { TextField("https://proxy.example.com", text: $url) }
            labelled("Read-only token") { SecureField("USAGE_LIMITS_TOKEN", text: $token) }
            Text("the token is stored in Keychain, clear the URL to go back to local discovery")
                .font(.detail).foregroundStyle(Color.dim)
            if let error { Text(error).font(.detail).foregroundStyle(Color.warn).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save", action: save).keyboardShortcut(.defaultAction).disabled(!tokenLoaded)
            }
        }
        .padding(20)
        .frame(width: 460)
        .font(.bodyStrong)
        .background(.black)
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .task {
            do {
                token = try CLIProxyToken.load()
                tokenLoaded = true
            } catch { self.error = (error as? UsageError)?.description ?? "could not read the CLI proxy token" }
        }
    }

    /// The Settings field style: Body text in a 5pt Stroke Grey outline.
    private func labelled(_ title: String, @ViewBuilder field: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
            field()
                .textFieldStyle(.plain).font(.body).padding(8)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.stroke))
                .accessibilityLabel(title)
        }
    }

    private func save() {
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if !trimmedURL.isEmpty {
                _ = try CLIProxyUsageSource.endpoint(for: trimmedURL)
                guard !trimmedToken.isEmpty else { throw UsageError.other("enter the proxy's read-only USAGE_LIMITS_TOKEN") }
            }
            var config = try Config.loadForUpdate()
            config.cliProxyURL = trimmedURL.isEmpty ? nil : trimmedURL
            let previousToken = try CLIProxyToken.load()
            try CLIProxyToken.save(trimmedURL.isEmpty ? "" : trimmedToken)
            do { try config.save() } catch {
                try CLIProxyToken.save(previousToken)
                throw error
            }
            onSaved(trimmedURL)
            dismiss()
        } catch { self.error = (error as? UsageError)?.description ?? "could not save the CLI proxy connection" }
    }
}
