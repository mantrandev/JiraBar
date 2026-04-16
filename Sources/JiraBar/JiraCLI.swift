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
        let trimmedSite = try self.validatedSite(site)

        let output = try await ShellCommandRunner.runInteractive(
            executableURL: self.zshURL,
            arguments: ["-lc", self.shellPreamble + "acli jira auth login --web"]
        ) { accumulated in
            let lines = accumulated.components(separatedBy: .newlines)
            guard lines.contains(where: { $0.contains(".atlassian.net") || $0.contains("Select") }) else {
                return nil
            }
            for line in lines {
                guard line.contains(trimmedSite) else { continue }
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if let digit = trimmed.first, digit.isNumber {
                    return "\(digit)\n"
                }
            }
            return "1\n"
        }

        guard output.exitCode == 0 else {
            throw ShellCommandError.failedCommand(output.combinedOutput)
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

    func moveForward(ticket: JiraTicket) async throws {
        guard let next = JiraWorkflowStatus.next(after: ticket.status) else {
            throw ShellCommandError.failedCommand("No next workflow state for \(ticket.key) (current: '\(ticket.status)').")
        }
        try await self.move(ticketKey: ticket.key, to: next)
    }

    func moveBackward(ticket: JiraTicket) async throws {
        guard let previous = JiraWorkflowStatus.previous(before: ticket.status) else {
            throw ShellCommandError.failedCommand("No previous workflow state for \(ticket.key) (current: '\(ticket.status)').")
        }
        try await self.move(ticketKey: ticket.key, to: previous)
    }

    func move(ticketKey: String, to status: JiraWorkflowStatus) async throws {
        try await self.runShell("acli jira workitem transition --key \(Self.escape(ticketKey)) --status \(Self.escape(status.rawValue)) --yes")
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
