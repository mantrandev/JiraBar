import Foundation

enum AppResources {
    static func jiraSnapshotScriptURL() -> URL? {
        #if SWIFT_PACKAGE
        return Bundle.module.url(forResource: "jira_snapshot", withExtension: "zsh")
        #else
        return Bundle.main.url(forResource: "jira_snapshot", withExtension: "zsh")
            ?? Bundle.main.resourceURL?.appending(path: "jira_snapshot.zsh")
        #endif
    }
}
