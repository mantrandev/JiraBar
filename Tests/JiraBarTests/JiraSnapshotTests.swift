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

    func testParseStatusesFromIssuesFieldsWrapped() {
        let json = """
        [
          {"key": "T-1", "fields": {"status": {"name": "To Do"}}},
          {"key": "T-2", "fields": {"status": {"name": "In Progress"}}},
          {"key": "T-3", "fields": {"status": {"name": "To Do"}}},
          {"key": "T-4", "fields": {"status": {"name": "Done"}}}
        ]
        """.data(using: .utf8)!
        let result = JiraCLI.parseStatusesFromIssues(from: json)
        XCTAssertEqual(result, ["To Do", "In Progress", "Done"])
    }

    func testParseStatusesFromIssuesObjectWrapper() {
        let json = """
        {
          "issues": [
            {"key": "T-1", "fields": {"status": {"name": "TO DO"}}},
            {"key": "T-2", "fields": {"status": {"name": "REVIEW"}}},
            {"key": "T-3", "fields": {"status": {"name": "DONE"}}}
          ]
        }
        """.data(using: .utf8)!
        let result = JiraCLI.parseStatusesFromIssues(from: json)
        XCTAssertEqual(result, ["TO DO", "REVIEW", "DONE"])
    }

    func testParseStatusesActualBoard() {
        // Statuses from the real project board via workitem search
        let json = """
        [
          {"key": "T-1", "fields": {"status": {"name": "TO DO"}}},
          {"key": "T-2", "fields": {"status": {"name": "IN PROGRESS"}}},
          {"key": "T-3", "fields": {"status": {"name": "TESTING"}}},
          {"key": "T-4", "fields": {"status": {"name": "BLOCK"}}},
          {"key": "T-5", "fields": {"status": {"name": "REVIEW"}}},
          {"key": "T-6", "fields": {"status": {"name": "WAIT TO BUILD PROD"}}},
          {"key": "T-7", "fields": {"status": {"name": "DONE"}}},
          {"key": "T-8", "fields": {"status": {"name": "IN PROGRESS"}}}
        ]
        """.data(using: .utf8)!
        let result = JiraCLI.parseStatusesFromIssues(from: json)
        XCTAssertEqual(result, ["TO DO", "IN PROGRESS", "TESTING", "BLOCK", "REVIEW", "WAIT TO BUILD PROD", "DONE"])
    }
}
