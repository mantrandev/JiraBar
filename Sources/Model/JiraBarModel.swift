import AppKit
import Combine
import Foundation

@MainActor
final class JiraBarModel: ObservableObject {
    private enum DefaultsKey {
        static let refreshInterval = "jirabar.refreshInterval"
        static let maxItemsPerSection = "jirabar.maxItemsPerSection"
        static let preferredSite = "jirabar.preferredSite"
        static let projectStatuses = "jirabar.projectStatuses"
    }

    @Published var snapshot: JiraSnapshot = .empty
    @Published var projectStatuses: [String] = []
    @Published var refreshInterval: RefreshInterval {
        didSet {
            UserDefaults.standard.set(self.refreshInterval.rawValue, forKey: DefaultsKey.refreshInterval)
            self.restartRefreshLoop()
        }
    }
    @Published var maxItemsPerSection: Int {
        didSet {
            UserDefaults.standard.set(self.maxItemsPerSection, forKey: DefaultsKey.maxItemsPerSection)
        }
    }
    @Published var preferredSite: String {
        didSet {
            UserDefaults.standard.set(
                self.preferredSite.trimmingCharacters(in: .whitespacesAndNewlines),
                forKey: DefaultsKey.preferredSite)
        }
    }
    @Published var isRefreshing = false
    @Published var isPerformingAction = false
    @Published var actingOnTicketKey: String?
    @Published var isLoadingInitialSnapshot = true
    @Published var lastActionMessage: String?
    @Published var lastErrorMessage: String?

    private let cli: JiraCLI
    private var refreshTask: Task<Void, Never>?

    init(cli: JiraCLI = JiraCLI()) {
        self.cli = cli
        let storedInterval = UserDefaults.standard.string(forKey: DefaultsKey.refreshInterval)
            .flatMap(RefreshInterval.init(rawValue:))
        self.refreshInterval = storedInterval ?? .twoMinutes

        let storedMaxItems = UserDefaults.standard.integer(forKey: DefaultsKey.maxItemsPerSection)
        self.maxItemsPerSection = storedMaxItems == 0 ? 8 : min(max(storedMaxItems, 3), 20)
        self.preferredSite = UserDefaults.standard.string(forKey: DefaultsKey.preferredSite) ?? ""
        self.projectStatuses = UserDefaults.standard.stringArray(forKey: DefaultsKey.projectStatuses) ?? []

        self.restartRefreshLoop()
        Task {
            await self.refresh(force: true)
            if self.projectStatuses.isEmpty && self.snapshot.auth.authorized {
                await self.fetchAndCacheStatuses()
            }
        }
    }

    deinit {
        self.refreshTask?.cancel()
    }

    var menuBarTitle: String {
        if self.isLoadingInitialSnapshot {
            return "Jira …"
        }
        if !self.snapshot.auth.authorized {
            return "Jira Login"
        }
        let total = self.snapshot.bugs.count + self.snapshot.tasks.count
        if self.isRefreshing && total == 0 {
            return "Jira …"
        }
        return "Jira \(total)"
    }

    var menuBarSymbolName: String {
        if !self.snapshot.auth.authorized {
            return "lock.slash"
        }
        if self.isPerformingAction {
            return "arrow.triangle.2.circlepath"
        }
        if self.snapshot.bugs.isEmpty && self.snapshot.tasks.isEmpty {
            return "checkmark.circle"
        }
        return "ticket"
    }

    var menuBarImage: NSImage? {
        guard self.snapshot.auth.authorized, !self.isPerformingAction else {
            return nil
        }
        guard let url = AppResources.menuBarIconURL(),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }

    var visibleStories: [JiraTicket] {
        Array(self.snapshot.stories.prefix(self.maxItemsPerSection))
    }

    var visibleBugs: [JiraTicket] {
        Array(self.snapshot.bugs.prefix(self.maxItemsPerSection))
    }

    var visibleTasks: [JiraTicket] {
        Array(self.snapshot.tasks.prefix(self.maxItemsPerSection))
    }

    var lastRefreshDescription: String {
        guard self.snapshot.fetchedAt > .distantPast else { return "Never" }
        return Self.relativeFormatter.localizedString(for: self.snapshot.fetchedAt, relativeTo: .now)
    }

    func refresh(force: Bool) async {
        if self.isRefreshing { return }
        if !force,
           self.snapshot.fetchedAt > .distantPast,
           Date().timeIntervalSince(self.snapshot.fetchedAt) < 20
        {
            return
        }

        self.isRefreshing = true
        defer {
            self.isRefreshing = false
            self.isLoadingInitialSnapshot = false
        }

        do {
            let snapshot = try await self.cli.fetchSnapshot()
            self.snapshot = snapshot
            self.lastErrorMessage = snapshot.errorMessage
            if !snapshot.site.isEmpty, snapshot.site != self.preferredSite {
                self.preferredSite = snapshot.site
            }
            if snapshot.auth.authorized {
                self.lastActionMessage = nil
            }
        } catch {
            self.lastErrorMessage = error.localizedDescription
        }
    }

    func login() {
        guard !self.isPerformingAction else { return }
        self.isPerformingAction = true
        self.lastActionMessage = "Complete Jira login in your browser."
        self.lastErrorMessage = nil
        Task {
            defer { self.isPerformingAction = false }
            do {
                try await self.cli.login(site: self.preferredSite)
                await self.refresh(force: true)
                await self.fetchAndCacheStatuses()
                self.lastActionMessage = "Jira login successful."
            } catch {
                self.lastErrorMessage = error.localizedDescription
            }
        }
    }

    func logout() {
        self.projectStatuses = []
        self.preferredSite = ""
        self.refreshInterval = .twoMinutes
        self.maxItemsPerSection = 8
        UserDefaults.standard.removeObject(forKey: DefaultsKey.projectStatuses)
        UserDefaults.standard.removeObject(forKey: DefaultsKey.preferredSite)
        UserDefaults.standard.removeObject(forKey: DefaultsKey.refreshInterval)
        UserDefaults.standard.removeObject(forKey: DefaultsKey.maxItemsPerSection)
        self.snapshot = .empty
        self.lastActionMessage = nil
        self.lastErrorMessage = nil
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.cli.logout()
            } catch {
                self.lastErrorMessage = error.localizedDescription
            }
        }
    }

    func switchAccount() {
        guard !self.isPerformingAction else { return }
        self.isPerformingAction = true
        self.lastActionMessage = "Complete account switching in your browser."
        self.lastErrorMessage = nil
        Task {
            defer { self.isPerformingAction = false }
            do {
                try await self.cli.login(site: self.preferredSite)
                await self.refresh(force: true)
                await self.fetchAndCacheStatuses()
                self.lastActionMessage = "Jira account updated."
            } catch {
                self.lastErrorMessage = error.localizedDescription
            }
        }
    }

    func openInBrowser(_ ticket: JiraTicket) async {
        await self.runAction(ticketKey: ticket.key, progress: "Opening \(ticket.key)…", refreshAfter: false) {
            try await self.cli.openInBrowser(ticketKey: ticket.key)
            return "Opened \(ticket.key) in the browser."
        }
    }

    func assignToMe(_ ticket: JiraTicket) async {
        await self.runAction(ticketKey: ticket.key, progress: "Assigning \(ticket.key)…") {
            try await self.cli.assignToMe(ticketKey: ticket.key)
            return "Assigned \(ticket.key) to you."
        }
    }

    func moveForward(_ ticket: JiraTicket) async {
        let statuses = self.projectStatuses
        await self.runAction(ticketKey: ticket.key, progress: "Moving \(ticket.key) forward…") {
            try await self.cli.moveForward(ticket: ticket, statuses: statuses)
            return "Moved \(ticket.key) to the next workflow state."
        }
    }

    func moveBackward(_ ticket: JiraTicket) async {
        let statuses = self.projectStatuses
        await self.runAction(ticketKey: ticket.key, progress: "Moving \(ticket.key) backward…") {
            try await self.cli.moveBackward(ticket: ticket, statuses: statuses)
            return "Moved \(ticket.key) to the previous workflow state."
        }
    }

    func move(_ ticket: JiraTicket, to statusName: String) async {
        await self.runAction(ticketKey: ticket.key, progress: "Moving \(ticket.key) to \(statusName)…") {
            try await self.cli.move(ticketKey: ticket.key, to: statusName)
            return "Moved \(ticket.key) to \(statusName)."
        }
    }

    func refreshStatuses() {
        Task { await self.fetchAndCacheStatuses() }
    }

    private func fetchAndCacheStatuses() async {
        let firstKey = self.snapshot.stories.first?.key ?? self.snapshot.bugs.first?.key ?? self.snapshot.tasks.first?.key ?? ""
        let projectKey = String(firstKey.split(separator: "-").first ?? "")
        guard !projectKey.isEmpty else {
            self.lastErrorMessage = "No project key — make sure tickets are loaded first."
            return
        }
        do {
            let fetched = try await self.cli.fetchStatuses(projectKey: projectKey)
            self.projectStatuses = fetched
            UserDefaults.standard.set(fetched, forKey: DefaultsKey.projectStatuses)
        } catch {
            self.lastErrorMessage = "Statuses: \(error.localizedDescription)"
        }
    }

    private func runAction(
        ticketKey: String,
        progress: String,
        refreshAfter: Bool = true,
        operation: @escaping @Sendable () async throws -> String) async
    {
        guard self.actingOnTicketKey == nil else { return }

        self.actingOnTicketKey = ticketKey
        self.lastActionMessage = progress
        self.lastErrorMessage = nil

        do {
            let message = try await operation()
            self.lastActionMessage = message
            self.actingOnTicketKey = nil
            if refreshAfter {
                Task { await self.refresh(force: true) }
            }
        } catch {
            self.lastErrorMessage = error.localizedDescription
            self.actingOnTicketKey = nil
        }
    }

    private func restartRefreshLoop() {
        self.refreshTask?.cancel()
        guard let seconds = self.refreshInterval.seconds else {
            self.refreshTask = nil
            return
        }

        self.refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(seconds))
                guard let self else { break }
                await self.refresh(force: true)
            }
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}
