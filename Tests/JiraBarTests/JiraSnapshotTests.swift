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

    func testDecodesSnapshotIgnoresUnknownFields() throws {
        let json = """
        {
          "site": "example.atlassian.net",
          "auth": { "authorized": true, "description": "Authenticated" },
          "stories": [], "tickets": [],
          "statusesByType": {"Bug": ["To Do", "Done"]},
          "projectStatuses": ["To Do", "Done"],
          "errorMessage": null,
          "fetchedAt": "2026-04-16T13:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(JiraSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(snapshot.site, "example.atlassian.net")
        XCTAssertTrue(snapshot.tickets.isEmpty)
    }

    func testParseStatusesPerTypeFormat() {
        let json = """
        [
          {"name": "Story", "statuses": [{"name": "To Do"}, {"name": "In Progress"}, {"name": "Done"}]},
          {"name": "Bug", "statuses": [{"name": "To Do"}, {"name": "Testing"}, {"name": "Done"}]}
        ]
        """.data(using: .utf8)!
        let result = JiraCLI.parseStatuses(from: json)
        XCTAssertEqual(result["Story"], ["To Do", "In Progress", "Done"])
        XCTAssertEqual(result["Bug"], ["To Do", "Testing", "Done"])
    }

    func testParseStatusesFlatFormat() {
        let json = """
        [{"name": "To Do"}, {"name": "In Progress"}, {"name": "Done"}]
        """.data(using: .utf8)!
        let result = JiraCLI.parseStatuses(from: json)
        XCTAssertEqual(result["*"], ["To Do", "In Progress", "Done"])
    }

    func testParseStatusesActualBoard() {
        // Statuses from the real project board
        let json = """
        [
          {"name": "TO DO"},
          {"name": "IN PROGRESS"},
          {"name": "TESTING"},
          {"name": "BLOCK"},
          {"name": "REVIEW"},
          {"name": "WAIT TO BUILD PROD"},
          {"name": "DONE"}
        ]
        """.data(using: .utf8)!
        let result = JiraCLI.parseStatuses(from: json)
        XCTAssertEqual(result["*"], ["TO DO", "IN PROGRESS", "TESTING", "BLOCK", "REVIEW", "WAIT TO BUILD PROD", "DONE"])
    }
}
