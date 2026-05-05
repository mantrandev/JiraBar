import Foundation

struct JiraSnapshot: Equatable, Sendable {
    var boardName: String?
    var accountEmail: String?
    var site: String
    var auth: JiraAuthState
    var stories: [JiraTicket]
    var tickets: [JiraTicket]
    var projectStatuses: [String]
    var errorMessage: String?
    var fetchedAt: Date

    static let empty = JiraSnapshot(
        boardName: nil,
        accountEmail: nil,
        site: "",
        auth: .loggedOut,
        stories: [],
        tickets: [],
        projectStatuses: [],
        errorMessage: nil,
        fetchedAt: .distantPast)
}

extension JiraSnapshot: Codable {
    private enum CodingKeys: String, CodingKey {
        case boardName, accountEmail, site, auth, stories, tickets, projectStatuses, errorMessage, fetchedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.boardName = try c.decodeIfPresent(String.self, forKey: .boardName)
        self.accountEmail = try c.decodeIfPresent(String.self, forKey: .accountEmail)
        self.site = try c.decode(String.self, forKey: .site)
        self.auth = try c.decode(JiraAuthState.self, forKey: .auth)
        self.stories = try c.decode([JiraTicket].self, forKey: .stories)
        self.tickets = try c.decode([JiraTicket].self, forKey: .tickets)
        self.projectStatuses = (try c.decodeIfPresent([String].self, forKey: .projectStatuses)) ?? []
        self.errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
        self.fetchedAt = try c.decode(Date.self, forKey: .fetchedAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(self.boardName, forKey: .boardName)
        try c.encodeIfPresent(self.accountEmail, forKey: .accountEmail)
        try c.encode(self.site, forKey: .site)
        try c.encode(self.auth, forKey: .auth)
        try c.encode(self.stories, forKey: .stories)
        try c.encode(self.tickets, forKey: .tickets)
        try c.encode(self.projectStatuses, forKey: .projectStatuses)
        try c.encodeIfPresent(self.errorMessage, forKey: .errorMessage)
        try c.encode(self.fetchedAt, forKey: .fetchedAt)
    }
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
