import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: JiraBarModel
    @State private var draftPreferredSite: String

    init(model: JiraBarModel) {
        self.model = model
        self._draftPreferredSite = State(initialValue: model.preferredSite)
    }

    var body: some View {
        Form {
            Section("Workspace") {
                LabeledContent("Board", value: self.model.snapshot.boardName ?? "Not detected yet")
                LabeledContent("Account", value: self.model.snapshot.accountEmail ?? "Not detected yet")
                LabeledContent("Connected Site", value: self.model.snapshot.site.isEmpty ? "Not loaded yet" : self.model.snapshot.site)
                LabeledContent("Auth", value: self.model.snapshot.auth.authorized ? "Authorized" : "Logged out")
                LabeledContent("Preferred Site", value: self.model.preferredSite.isEmpty ? "Not set" : self.model.preferredSite)
                TextField("Preferred Site", text: self.$draftPreferredSite, prompt: Text("your-team.atlassian.net"))
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Save Site") {
                        self.savePreferredSite()
                    }
                    .disabled(!self.hasPendingPreferredSiteChanges)

                    if self.hasPendingPreferredSiteChanges {
                        Button("Reset") {
                            self.draftPreferredSite = self.model.preferredSite
                        }
                    }
                }

                if !self.model.preferredSite.isEmpty {
                    Text("Login will switch to: \(self.model.preferredSite)")
                        .foregroundStyle(.secondary)
                }

                if !self.model.snapshot.site.isEmpty && self.model.snapshot.site != self.model.preferredSite {
                    Button("Use Connected Site") {
                        self.draftPreferredSite = self.model.snapshot.site
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
                    Task { self.model.login() }
                }
                .disabled(self.model.isPerformingAction)

                Button("Switch Account") {
                    Task { self.model.switchAccount() }
                }
                .disabled(self.model.preferredSite.isEmpty)

                Button("Logout") {
                    self.model.logout()
                }
                .disabled(!self.model.snapshot.auth.authorized)
            }

            if let message = self.model.lastActionMessage, !message.isEmpty {
                Section("Status") {
                    Text(message)
                        .foregroundStyle(.secondary)
                }
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
        .onChange(of: self.model.preferredSite) { _, newValue in
            if !self.hasPendingPreferredSiteChanges {
                self.draftPreferredSite = newValue
            }
        }
    }

    private var normalizedDraftPreferredSite: String {
        self.draftPreferredSite.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasPendingPreferredSiteChanges: Bool {
        self.normalizedDraftPreferredSite != self.model.preferredSite
    }

    private func savePreferredSite() {
        self.model.preferredSite = self.normalizedDraftPreferredSite
        self.draftPreferredSite = self.model.preferredSite
    }
}
