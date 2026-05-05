import AppKit
import Combine
import Foundation

@MainActor
final class JiraBarModel: ObservableObject {
    private enum DefaultsKey {
        static let refreshInterval = "jirabar.refreshInterval"
        static let maxItemsPerSection = "jirabar.maxItemsPerSection"
        static let preferredSite = "jirabar.preferredSite"
    }

    @Published var snapshot: JiraSnapshot = .empty
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

        self.restartRefreshLoop()
        Task { await self.refresh(force: true) }
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
        if self.isRefreshing && self.snapshot.tickets.isEmpty {
            return "Jira …"
        }
        return "Jira \(self.snapshot.tickets.count)"
    }

    var menuBarSymbolName: String {
        if !self.snapshot.auth.authorized {
            return "lock.slash"
        }
        if self.isPerformingAction {
            return "arrow.triangle.2.circlepath"
        }
        if self.snapshot.tickets.isEmpty {
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

    var visibleTickets: [JiraTicket] {
        Array(self.snapshot.tickets.prefix(self.maxItemsPerSection))
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
                self.lastActionMessage = "Jira login successful."
            } catch {
                self.lastErrorMessage = error.localizedDescription
            }
        }
    }

    func logout() {
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
                self.lastActionMessage = "Jira account updated."
            } catch {
                self.lastErrorMessage = error.localizedDescription
            }
        }
    }

    func openInBrowser(_ ticket: JiraTicket) async {
        await self.runAction(progress: "Opening \(ticket.key)…", refreshAfter: false) {
            try await self.cli.openInBrowser(ticketKey: ticket.key)
            return "Opened \(ticket.key) in the browser."
        }
    }

    func assignToMe(_ ticket: JiraTicket) async {
        await self.runAction(progress: "Assigning \(ticket.key)…") {
            try await self.cli.assignToMe(ticketKey: ticket.key)
            return "Assigned \(ticket.key) to you."
        }
    }

    func moveForward(_ ticket: JiraTicket) async {
        await self.runAction(progress: "Moving \(ticket.key) forward…") {
            try await self.cli.moveForward(ticket: ticket, statuses: self.snapshot.projectStatuses)
            return "Moved \(ticket.key) to the next workflow state."
        }
    }

    func moveBackward(_ ticket: JiraTicket) async {
        await self.runAction(progress: "Moving \(ticket.key) backward…") {
            try await self.cli.moveBackward(ticket: ticket, statuses: self.snapshot.projectStatuses)
            return "Moved \(ticket.key) to the previous workflow state."
        }
    }

    func move(_ ticket: JiraTicket, to statusName: String) async {
        await self.runAction(progress: "Moving \(ticket.key) to \(statusName)…") {
            try await self.cli.move(ticketKey: ticket.key, to: statusName)
            return "Moved \(ticket.key) to \(statusName)."
        }
    }

    private func runAction(
        progress: String,
        refreshAfter: Bool = true,
        operation: @escaping @Sendable () async throws -> String) async
    {
        if self.isPerformingAction { return }

        self.isPerformingAction = true
        self.lastActionMessage = progress
        self.lastErrorMessage = nil
        defer { self.isPerformingAction = false }

        do {
            let message = try await operation()
            self.lastActionMessage = message
            if refreshAfter {
                await self.refresh(force: true)
            }
        } catch {
            self.lastErrorMessage = error.localizedDescription
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
