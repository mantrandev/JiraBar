import AppKit
import SwiftUI

@main
struct JiraBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = JiraBarModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(model: self.model)
        } label: {
            Label(self.model.menuBarTitle, systemImage: self.model.menuBarSymbolName)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(model: self.model)
        }
    }
}
