import Foundation

struct JiraSnapshot: Codable, Equatable, Sendable {
    var boardName: String?
    var accountEmail: String?
    var site: String
    var auth: JiraAuthState
    var stories: [JiraTicket]
    var tickets: [JiraTicket]
    var errorMessage: String?
    var fetchedAt: Date

    static let empty = JiraSnapshot(
        boardName: nil,
        accountEmail: nil,
        site: "",
        auth: .loggedOut,
        stories: [],
        tickets: [],
        errorMessage: nil,
        fetchedAt: .distantPast)
}

struct JiraAuthState: Codable, Equatable, Sendable {
    var authorized: Bool
    var description: String

    static let loggedOut = JiraAuthState(
        authorized: false,
        description: "Not authenticated. Use Login to connect Jira.")
}

struct JiraTicket: Codable, Equatable, Identifiable, Sendable {
    var issueType: String
    var key: String
    var status: String
    var summary: String

    var id: String { self.key }

    var menuTitle: String {
        "\(self.key)  \(self.summary)"
    }

    var statusLine: String {
        if self.status.isEmpty {
            return self.issueType
        }
        if self.issueType.isEmpty {
            return self.status
        }
        return "\(self.issueType) • \(self.status)"
    }
}

enum JiraWorkflowStatus: String, CaseIterable, Identifiable, Sendable {
    case todo = "TO DO"
    case inProgress = "In Progress"
    case testing = "Testing"
    case block = "Block"
    case review = "Review"
    case prod = "Wait to build PROD"
    case done = "DONE"

    var id: String { self.rawValue }

    var label: String { self.rawValue }

    static let orderedStatuses: [JiraWorkflowStatus] = [
        .todo,
        .inProgress,
        .testing,
        .block,
        .review,
        .prod,
        .done,
    ]

    static func from(statusText: String) -> JiraWorkflowStatus? {
        let normalized = statusText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return Self.orderedStatuses.first { status in
            status.rawValue.lowercased() == normalized
        }
    }

    static func next(after statusText: String) -> JiraWorkflowStatus? {
        guard let currentIndex = Self.orderedStatuses.firstIndex(where: { $0.rawValue.caseInsensitiveCompare(statusText) == .orderedSame })
        else {
            return nil
        }
        let nextIndex = Self.orderedStatuses.index(after: currentIndex)
        guard nextIndex < Self.orderedStatuses.endIndex else { return nil }
        return Self.orderedStatuses[nextIndex]
    }

    static func previous(before statusText: String) -> JiraWorkflowStatus? {
        guard let currentIndex = Self.orderedStatuses.firstIndex(where: { $0.rawValue.caseInsensitiveCompare(statusText) == .orderedSame })
        else {
            return nil
        }
        guard currentIndex > Self.orderedStatuses.startIndex else { return nil }
        return Self.orderedStatuses[Self.orderedStatuses.index(before: currentIndex)]
    }
}

enum RefreshInterval: String, CaseIterable, Identifiable, Sendable {
    case manual
    case thirtySeconds
    case oneMinute
    case twoMinutes
    case fiveMinutes

    var id: String { self.rawValue }

    var label: String {
        switch self {
        case .manual: "Manual"
        case .thirtySeconds: "30 sec"
        case .oneMinute: "1 min"
        case .twoMinutes: "2 min"
        case .fiveMinutes: "5 min"
        }
    }

    var seconds: TimeInterval? {
        switch self {
        case .manual: nil
        case .thirtySeconds: 30
        case .oneMinute: 60
        case .twoMinutes: 120
        case .fiveMinutes: 300
        }
    }
}
