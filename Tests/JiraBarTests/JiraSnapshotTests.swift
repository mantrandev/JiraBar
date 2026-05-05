import Foundation
import XCTest
@testable import JiraBar

final class JiraSnapshotTests: XCTestCase {
    func testDecodesSnapshotPayload() throws {
        let json = """
        {
          "boardName": "Personal Scrum",
          "accountEmail": "person@example.com",
          "site": "example.atlassian.net",
          "auth": {
            "authorized": true,
            "description": "Authenticated"
          },
          "stories": [
            {
              "issueType": "Story",
              "key": "TEAM-100",
              "status": "In Progress",
              "summary": "Parent story"
            }
          ],
          "tickets": [
            {
              "issueType": "Task",
              "key": "TEAM-101",
              "status": "Testing",
              "summary": "Child ticket"
            }
          ],
          "errorMessage": null,
          "fetchedAt": "2026-04-16T13:00:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(JiraSnapshot.self, from: Data(json.utf8))

        XCTAssertEqual(snapshot.boardName, "Personal Scrum")
        XCTAssertEqual(snapshot.accountEmail, "person@example.com")
        XCTAssertTrue(snapshot.auth.authorized)
        XCTAssertEqual(snapshot.stories.first?.key, "TEAM-100")
        XCTAssertEqual(snapshot.tickets.first?.summary, "Child ticket")
    }

    func testDecodesStatusesByTypeWhenPresent() throws {
        let json = """
        {
          "site": "example.atlassian.net",
          "auth": { "authorized": true, "description": "Authenticated" },
          "stories": [], "tickets": [],
          "statusesByType": {
            "Story": ["To Do", "In Progress", "Done"],
            "Bug": ["To Do", "In Progress", "Testing", "Done"]
          },
          "errorMessage": null,
          "fetchedAt": "2026-04-16T13:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(JiraSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(snapshot.statusesByType["Story"], ["To Do", "In Progress", "Done"])
        XCTAssertEqual(snapshot.statusesByType["Bug"], ["To Do", "In Progress", "Testing", "Done"])
    }

    func testStatusesByTypeDefaultsToEmptyWhenAbsent() throws {
        let json = """
        {
          "site": "example.atlassian.net",
          "auth": { "authorized": true, "description": "Authenticated" },
          "stories": [], "tickets": [],
          "errorMessage": null,
          "fetchedAt": "2026-04-16T13:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(JiraSnapshot.self, from: Data(json.utf8))
        XCTAssertTrue(snapshot.statusesByType.isEmpty)
    }

    func testStatusesForTicketUsesIssueType() throws {
        let snapshot = JiraSnapshot(
            boardName: nil, accountEmail: nil, site: "", auth: .loggedOut,
            stories: [], tickets: [],
            statusesByType: [
                "Story": ["To Do", "In Progress", "Done"],
                "Bug": ["To Do", "Testing", "Done"]
            ],
            errorMessage: nil, fetchedAt: .distantPast)
        let story = JiraTicket(issueType: "Story", key: "T-1", status: "To Do", summary: "")
        let bug = JiraTicket(issueType: "Bug", key: "T-2", status: "To Do", summary: "")
        let unknown = JiraTicket(issueType: "Epic", key: "T-3", status: "To Do", summary: "")
        XCTAssertEqual(snapshot.statuses(for: story), ["To Do", "In Progress", "Done"])
        XCTAssertEqual(snapshot.statuses(for: bug), ["To Do", "Testing", "Done"])
        XCTAssertTrue(snapshot.statuses(for: unknown).isEmpty)
    }
}
