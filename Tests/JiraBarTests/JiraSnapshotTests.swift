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

    func testDecodesProjectStatusesWhenPresent() throws {
        let json = """
        {
          "site": "example.atlassian.net",
          "auth": { "authorized": true, "description": "Authenticated" },
          "stories": [], "tickets": [],
          "projectStatuses": ["To Do", "In Progress", "Done"],
          "errorMessage": null,
          "fetchedAt": "2026-04-16T13:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(JiraSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(snapshot.projectStatuses, ["To Do", "In Progress", "Done"])
    }

    func testProjectStatusesDefaultsToEmptyWhenAbsent() throws {
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
        XCTAssertEqual(snapshot.projectStatuses, [])
    }
}
