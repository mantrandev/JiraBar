import Foundation

struct JiraCLI {
    private let zshURL = URL(fileURLWithPath: "/bin/zsh")

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
        let trimmedSite = site.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSite.isEmpty else {
            throw ShellCommandError.failedCommand("Set your Jira site in Settings before logging in.")
        }

        try self.launchShell(
            "source ~/.zshrc 2>/dev/null; exec acli jira auth login --web --site \(Self.escape(trimmedSite))")
    }

    func logout() async throws {
        try await self.runShell("source ~/.zshrc 2>/dev/null; acli jira auth logout")
    }

    func switchAccount(site: String) async throws {
        try await self.login(site: site)
    }

    func openInBrowser(ticketKey: String) async throws {
        try await self.runShell(
            "source ~/.zshrc 2>/dev/null; acli jira workitem view \(Self.escape(ticketKey)) --web")
    }

    func assignToMe(ticketKey: String) async throws {
        try await self.runShell(
            "source ~/.zshrc 2>/dev/null; acli jira workitem assign --key \(Self.escape(ticketKey)) --assignee '@me' --yes")
    }

    func moveForward(ticket: JiraTicket) async throws {
        guard let nextStatus = JiraWorkflowStatus.next(after: ticket.status) else {
            throw ShellCommandError.failedCommand("No next workflow state for \(ticket.key) from status '\(ticket.status)'.")
        }
        try await self.move(ticketKey: ticket.key, to: nextStatus)
    }

    func moveBackward(ticket: JiraTicket) async throws {
        guard let previousStatus = JiraWorkflowStatus.previous(before: ticket.status) else {
            throw ShellCommandError.failedCommand("No previous workflow state for \(ticket.key) from status '\(ticket.status)'.")
        }
        try await self.move(ticketKey: ticket.key, to: previousStatus)
    }

    func move(ticketKey: String, to status: JiraWorkflowStatus) async throws {
        try await self.runShell(
            "source ~/.zshrc 2>/dev/null; acli jira workitem transition --key \(Self.escape(ticketKey)) --status \(Self.escape(status.rawValue)) --yes")
    }

    private func runShell(_ script: String) async throws {
        let output = try await ShellCommandRunner.run(
            executableURL: self.zshURL,
            arguments: ["-lc", script])

        guard output.exitCode == 0 else {
            throw ShellCommandError.failedCommand(output.combinedOutput)
        }
    }

    private func launchShell(_ script: String) throws {
        try ShellCommandRunner.launch(
            executableURL: self.zshURL,
            arguments: ["-lc", script])
    }

    static func escape(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }
}
