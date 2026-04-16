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
            DispatchQueue.global(qos: .userInitiated).async {
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                let process = Process()
                process.executableURL = executableURL
                process.arguments = arguments
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe
                process.environment = Self.makeEnvironment(overrides: environment)

                do {
                    try process.run()
                    process.waitUntilExit()
                    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let output = ShellOutput(
                        exitCode: process.terminationStatus,
                        standardOutput: String(decoding: stdoutData, as: UTF8.self),
                        standardError: String(decoding: stderrData, as: UTF8.self))
                    continuation.resume(returning: output)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func launch(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]? = nil) throws
    {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = Self.makeEnvironment(overrides: environment)
        process.standardInput = FileHandle(forReadingAtPath: "/dev/null")
        process.standardOutput = FileHandle(forWritingAtPath: "/dev/null")
        process.standardError = FileHandle(forWritingAtPath: "/dev/null")
        try process.run()
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
