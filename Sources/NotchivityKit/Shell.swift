import Foundation

public struct ShellError: Error, CustomStringConvertible {
    public let description: String
}

public enum Shell {
    /// Runs a command to completion and returns stdout, throwing stderr on a non-zero exit.
    public static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 60) async throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = ["/opt/homebrew/bin", "/usr/local/bin", env["PATH"] ?? "/usr/bin:/bin"].joined(separator: ":")
        process.environment = env
        let stdout = Pipe(), stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let output = Task.detached { stdout.fileHandleForReading.readDataToEndOfFile() }
        let errors = Task.detached { stderr.fileHandleForReading.readDataToEndOfFile() }
        // The handler must be in place before launch: a fast command can exit before we
        // would otherwise get to register it, and the continuation would never resume.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { _ in continuation.resume() }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning { process.terminate() }
            }
        }
        let out = await output.value
        guard process.terminationStatus == 0 else {
            let message = String(decoding: await errors.value, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw ShellError(description: message.isEmpty ? "\(executable) exited \(process.terminationStatus)" : message)
        }
        return out
    }

    /// Resolves a command name through the login shell's PATH (gh lives in homebrew).
    public static func which(_ name: String) -> String {
        for dir in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"] {
            let path = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return name
    }

    /// One lowercase line for the notch. Raw stderr and URLError text stay in logs and `--doctor`.
    public static func summary(_ error: Error, fallback: String) -> String {
        if let shell = error as? ShellError, shell.description.localizedCaseInsensitiveContains("auth") { return "gh not signed in" }
        if error is URLError { return "github unreachable" }
        return fallback
    }
}
