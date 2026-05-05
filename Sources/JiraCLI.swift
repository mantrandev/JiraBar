import Foundation

struct JiraCLI {
    private let zshURL = URL(fileURLWithPath: "/bin/zsh")
    private let shellPreamble = "source ~/.zshrc 2>/dev/null; "

    func fetchSnapshot() async throws -> JiraSnapshot {
        guard let scriptURL = AppResources.jiraSnapshotScriptURL() else {
            throw ShellCommandError.missingExecutable("jira_snapshot.zsh")
        }

        let output = try await ShellCommandRunner.run(
            executableURL: self.zshURL,
            arguments: [scriptURL.path])

        guard output.exitCode == 0 else {
            throw ShellCommandError.failedCommand(output.combinedOutput)
        }

        let data = Data(output.standardOutput.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(JiraSnapshot.self, from: data)
    }

    func login(site: String) async throws {
        _ = try await ShellCommandRunner.runWithPTY(
            executableURL: self.zshURL,
            arguments: ["-lc", self.shellPreamble + "acli jira auth login --web"],
            environment: ["TERM": "xterm-256color"],
            autoRespond: { output in
                let plain = output.replacingOccurrences(
                    of: #"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])"#,
                    with: "",
                    options: .regularExpression)
                guard plain.contains("enter submit") || plain.contains("↑") else { return nil }
                return "\r"
            })

        let trimmedSite = site.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSite.isEmpty {
            try await self.runShell("acli jira auth switch --site \(Self.escape(trimmedSite))")
        }
    }

    func logout() async throws {
        try await self.runShell("acli jira auth logout")
    }

    func switchAccount(site: String) async throws {
        let trimmedSite = try self.validatedSite(site)
        try await self.runShell("acli jira auth switch --site \(Self.escape(trimmedSite))")
    }

    func openInBrowser(ticketKey: String) async throws {
        try await self.runShell("acli jira workitem view \(Self.escape(ticketKey)) --web")
    }

    func assignToMe(ticketKey: String) async throws {
        try await self.runShell("acli jira workitem assign --key \(Self.escape(ticketKey)) --assignee '@me' --yes")
    }

    func moveForward(ticket: JiraTicket, statuses: [String]) async throws {
        guard let next = Self.nextStatus(after: ticket.status, in: statuses) else {
            throw ShellCommandError.failedCommand("No next workflow state for \(ticket.key) (current: '\(ticket.status)').")
        }
        try await self.move(ticketKey: ticket.key, to: next)
    }

    func moveBackward(ticket: JiraTicket, statuses: [String]) async throws {
        guard let previous = Self.previousStatus(before: ticket.status, in: statuses) else {
            throw ShellCommandError.failedCommand("No previous workflow state for \(ticket.key) (current: '\(ticket.status)').")
        }
        try await self.move(ticketKey: ticket.key, to: previous)
    }

    func move(ticketKey: String, to statusName: String) async throws {
        try await self.runShell("acli jira workitem transition --key \(Self.escape(ticketKey)) --status \(Self.escape(statusName)) --yes")
    }

    private static func nextStatus(after statusText: String, in statuses: [String]) -> String? {
        guard let idx = statuses.firstIndex(where: { $0.caseInsensitiveCompare(statusText) == .orderedSame }),
              idx + 1 < statuses.count else { return nil }
        return statuses[idx + 1]
    }

    private static func previousStatus(before statusText: String, in statuses: [String]) -> String? {
        guard let idx = statuses.firstIndex(where: { $0.caseInsensitiveCompare(statusText) == .orderedSame }),
              idx > 0 else { return nil }
        return statuses[idx - 1]
    }

    private func validatedSite(_ site: String) throws -> String {
        let trimmed = site.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ShellCommandError.failedCommand("Set your Jira site in Settings before logging in.")
        }
        return trimmed
    }

    private func runShell(_ command: String) async throws {
        let output = try await ShellCommandRunner.run(
            executableURL: self.zshURL,
            arguments: ["-lc", self.shellPreamble + command])

        guard output.exitCode == 0 else {
            throw ShellCommandError.failedCommand(output.combinedOutput)
        }
    }

    private static func escape(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }
}
