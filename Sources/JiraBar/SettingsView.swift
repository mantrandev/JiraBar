import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: JiraBarModel

    var body: some View {
        Form {
            Section("Workspace") {
                LabeledContent("Board", value: self.model.snapshot.boardName ?? "Not detected yet")
                LabeledContent("Account", value: self.model.snapshot.accountEmail ?? "Not detected yet")
                LabeledContent("Connected Site", value: self.model.snapshot.site.isEmpty ? "Not loaded yet" : self.model.snapshot.site)
                LabeledContent("Auth", value: self.model.snapshot.auth.authorized ? "Authorized" : "Logged out")
                LabeledContent("Preferred Site", value: self.model.preferredSite.isEmpty ? "Not set" : self.model.preferredSite)
                TextField("Preferred Site", text: self.$model.preferredSite, prompt: Text("your-team.atlassian.net"))
                    .textFieldStyle(.roundedBorder)

                if self.model.preferredSite.isEmpty {
                    Text("Set your Jira domain here before logging in.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Login will use: \(self.model.preferredSite)")
                        .foregroundStyle(.secondary)
                }

                if !self.model.snapshot.site.isEmpty && self.model.snapshot.site != self.model.preferredSite {
                    Button("Use Connected Site") {
                        self.model.preferredSite = self.model.snapshot.site
                    }
                }
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
                .disabled(self.model.preferredSite.isEmpty)

                Button("Switch Account") {
                    Task { await self.model.switchAccount() }
                }
                .disabled(self.model.preferredSite.isEmpty)

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
