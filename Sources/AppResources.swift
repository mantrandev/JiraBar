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

    static func menuBarIconURL() -> URL? {
        #if SWIFT_PACKAGE
        return Bundle.module.url(forResource: "menubar_icon", withExtension: "svg")
        #else
        return Bundle.main.url(forResource: "menubar_icon", withExtension: "svg")
        #endif
    }

    static func jiraHelperScriptURL() -> URL? {
        #if SWIFT_PACKAGE
        return Bundle.module.url(forResource: "jira", withExtension: "zsh")
        #else
        return Bundle.main.url(forResource: "jira", withExtension: "zsh")
        #endif
    }
}
