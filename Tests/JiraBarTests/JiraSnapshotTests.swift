import Foundation
import Testing
@testable import JiraBar

struct JiraSnapshotTests {
    @Test
    func decodesSnapshotPayload() throws {
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

        #expect(snapshot.boardName == "Personal Scrum")
        #expect(snapshot.accountEmail == "person@example.com")
        #expect(snapshot.auth.authorized)
        #expect(snapshot.stories.first?.key == "TEAM-100")
        #expect(snapshot.tickets.first?.summary == "Child ticket")
    }

    @Test
    func workflowStatusLabelsMatchDirectJiraTransitions() {
        #expect(JiraWorkflowStatus.inProgress.label == "In Progress")
        #expect(JiraWorkflowStatus.prod.label == "Wait to build PROD")
        #expect(JiraWorkflowStatus.done.label == "DONE")
    }
}
