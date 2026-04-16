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
            MenuBarLabel(model: self.model)
        }
        .menuBarExtraStyle(.menu)

    }
}

private struct MenuBarLabel: View {
    @ObservedObject var model: JiraBarModel

    var body: some View {
        if let img = self.model.menuBarImage {
            Image(nsImage: img)
        } else {
            Label(self.model.menuBarTitle, systemImage: self.model.menuBarSymbolName)
        }
    }
}
