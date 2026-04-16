import Foundation

struct ShellOutput: Sendable {
    var exitCode: Int32
    var standardOutput: String
    var standardError: String

    var combinedOutput: String {
        let stdout = Self.sanitize(self.standardOutput)
        let stderr = Self.sanitize(self.standardError)
        if stdout.isEmpty { return stderr }
        if stderr.isEmpty { return stdout }
        return "\(stdout)\n\(stderr)"
    }

    private static func sanitize(_ text: String) -> String {
        guard !text.isEmpty else { return "" }

        var sanitized = text.replacingOccurrences(
            of: #"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])"#,
            with: "",
            options: .regularExpression)

        sanitized = sanitized.replacingOccurrences(of: "\r", with: "\n")
        sanitized = sanitized.replacingOccurrences(
            of: #"[^\P{Cc}\n\t]"#,
            with: "",
            options: .regularExpression)
        sanitized = sanitized.replacingOccurrences(
            of: #"\n{3,}"#,
            with: "\n\n",
            options: .regularExpression)

        return sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum ShellCommandError: LocalizedError {
    case missingExecutable(String)
    case failedCommand(String)

    var errorDescription: String? {
        switch self {
        case .missingExecutable(let name):
            "Missing executable: \(name)"
        case .failedCommand(let message):
            message
        }
    }
}

private final class InteractiveState: @unchecked Sendable {
    let lock = NSLock()
    var stdout = ""
    var stderr = ""
    var responded = false
}

enum ShellCommandRunner {
    private static let fallbackPath = [
        "/opt/homebrew/bin",
        "/opt/homebrew/sbin",
        "/usr/local/bin",
        "/usr/local/sbin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin",
    ].joined(separator: ":")

    static func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]? = nil) async throws -> ShellOutput
    {
        try await withCheckedThrowingContinuation { continuation in
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            let process = Self.makeProcess(executableURL: executableURL, arguments: arguments, environment: environment)
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            process.terminationHandler = { p in
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: ShellOutput(
                    exitCode: p.terminationStatus,
                    standardOutput: String(decoding: stdoutData, as: UTF8.self),
                    standardError: String(decoding: stderrData, as: UTF8.self)))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    static func runInteractive(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        autoRespond: @escaping @Sendable (String) -> String?) async throws -> ShellOutput
    {
        try await withCheckedThrowingContinuation { continuation in
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            let stdinPipe = Pipe()
            let process = Self.makeProcess(executableURL: executableURL, arguments: arguments, environment: environment)
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            process.standardInput = stdinPipe

            let state = InteractiveState()

            let considerResponse: @Sendable () -> Void = {
                state.lock.lock()
                defer { state.lock.unlock() }
                guard !state.responded else { return }
                if let reply = autoRespond(state.stdout + state.stderr) {
                    state.responded = true
                    stdinPipe.fileHandleForWriting.write(Data(reply.utf8))
                    stdinPipe.fileHandleForWriting.closeFile()
                }
            }

            stdoutPipe.fileHandleForReading.readabilityHandler = { fh in
                let chunk = fh.availableData
                guard !chunk.isEmpty else { return }
                state.lock.lock(); state.stdout += String(decoding: chunk, as: UTF8.self); state.lock.unlock()
                considerResponse()
            }

            stderrPipe.fileHandleForReading.readabilityHandler = { fh in
                let chunk = fh.availableData
                guard !chunk.isEmpty else { return }
                state.lock.lock(); state.stderr += String(decoding: chunk, as: UTF8.self); state.lock.unlock()
                considerResponse()
            }

            process.terminationHandler = { p in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                state.lock.lock()
                let stdout = state.stdout
                let stderr = state.stderr
                state.lock.unlock()
                continuation.resume(returning: ShellOutput(
                    exitCode: p.terminationStatus,
                    standardOutput: stdout,
                    standardError: stderr))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    static func launch(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]? = nil) throws
    {
        let process = Self.makeProcess(executableURL: executableURL, arguments: arguments, environment: environment)
        process.standardInput = FileHandle(forReadingAtPath: "/dev/null")
        process.standardOutput = FileHandle(forWritingAtPath: "/dev/null")
        process.standardError = FileHandle(forWritingAtPath: "/dev/null")
        try process.run()
    }

    private static func makeProcess(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]?) -> Process
    {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = Self.makeEnvironment(overrides: environment)
        return process
    }

    private static func makeEnvironment(overrides: [String: String]?) -> [String: String] {
        var merged = ProcessInfo.processInfo.environment
        let existingPath = merged["PATH"] ?? ""
        if existingPath.isEmpty {
            merged["PATH"] = Self.fallbackPath
        } else if !existingPath.contains("/opt/homebrew/bin") || !existingPath.contains("/usr/local/bin") {
            merged["PATH"] = "\(Self.fallbackPath):\(existingPath)"
        }
        merged["TERM"] = merged["TERM"] ?? "dumb"
        overrides?.forEach { merged[$0.key] = $0.value }
        return merged
    }
}
