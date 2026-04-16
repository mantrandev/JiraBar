import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: JiraBarModel

    var body: some View {
        Form {
            Section("Workspace") {
                LabeledContent("Board", value: self.model.snapshot.boardName ?? "Not detected yet")
                LabeledContent("Account", value: self.model.snapshot.accountEmail ?? "Not detected yet")
                LabeledContent("Site", value: self.model.snapshot.site.isEmpty ? "Not loaded yet" : self.model.snapshot.site)
                LabeledContent("Auth", value: self.model.snapshot.auth.authorized ? "Authorized" : "Logged out")
                TextField("Preferred Site", text: self.$model.preferredSite, prompt: Text("your-team.atlassian.net"))
            }

            Section("Refresh") {
                Picker("Interval", selection: self.$model.refreshInterval) {
                    ForEach(RefreshInterval.allCases) { interval in
                        Text(interval.label).tag(interval)
                    }
                }

                Stepper(value: self.$model.maxItemsPerSection, in: 3...20) {
                    Text("Items per section: \(self.model.maxItemsPerSection)")
                }
            }

            Section("Commands") {
                Button("Refresh Now") {
                    Task { await self.model.refresh(force: true) }
                }

                Button("Login") {
                    Task { await self.model.login() }
                }

                Button("Switch Account") {
                    Task { await self.model.switchAccount() }
                }
                .disabled(!self.model.snapshot.auth.authorized)

                Button("Logout") {
                    Task { await self.model.logout() }
                }
                .disabled(!self.model.snapshot.auth.authorized)
            }

            if let error = self.model.lastErrorMessage, !error.isEmpty {
                Section("Last Error") {
                    Text(error)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 420)
    }
}
