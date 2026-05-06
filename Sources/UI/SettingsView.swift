import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: JiraBarModel
    @State private var draftPreferredSite: String
    @State private var acliStatus: CLIStatus = .checking
    @State private var jqStatus: CLIStatus = .checking
    @State private var helperStatus: HelperStatus = .checking
    @State private var isInstallingHelper = false

    private enum CLIStatus {
        case checking
        case installed(String)
        case notInstalled
    }

    private enum HelperStatus {
        case checking
        case installed
        case notInstalled
    }

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

                Toggle("Launch at Login", isOn: self.$model.launchAtLogin)
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

            Section("CLI Tools") {
                self.cliToolRow(name: "acli", status: self.acliStatus, brew: "atlassian/tap/acli")
                self.cliToolRow(name: "jq", status: self.jqStatus, brew: "jq")
                Button("Re-check") {
                    self.acliStatus = .checking
                    self.jqStatus = .checking
                    Task { await self.checkCLITools() }
                }
            }

            Section("Shell Helpers") {
                switch self.helperStatus {
                case .checking:
                    LabeledContent("jira.zsh", value: "Checking…")
                case .installed:
                    LabeledContent("jira.zsh", value: "Installed")
                    Button("Update") {
                        Task { await self.installShellHelpers() }
                    }
                    .disabled(self.isInstallingHelper)
                case .notInstalled:
                    LabeledContent("jira.zsh") {
                        Text("Not installed")
                            .foregroundStyle(.secondary)
                    }
                    Button("Install") {
                        Task { await self.installShellHelpers() }
                    }
                    .disabled(self.isInstallingHelper)
                }
                Text("Copies jira.zsh to ~/.jira.zsh and adds `source ~/.jira.zsh` to ~/.zshrc. Provides jv, jm, jforward, jmine, jstories and ~40 more commands.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 420)
        .task { await self.checkCLITools(); await self.checkHelperInstalled() }
        .onChange(of: self.model.preferredSite) { _, newValue in
            if !self.hasPendingPreferredSiteChanges {
                self.draftPreferredSite = newValue
            }
        }
    }

    @ViewBuilder
    private func cliToolRow(name: String, status: CLIStatus, brew: String) -> some View {
        switch status {
        case .checking:
            LabeledContent(name, value: "Checking…")
        case .installed(let version):
            LabeledContent(name, value: version)
        case .notInstalled:
            LabeledContent(name) {
                HStack {
                    Text("Not installed")
                        .foregroundStyle(.red)
                    Button("Install with Homebrew") {
                        self.installViaBrew(brew)
                    }
                }
            }
        }
    }

    private func checkCLITools() async {
        let zsh = URL(fileURLWithPath: "/bin/zsh")
        let preamble = "source ~/.zshrc 2>/dev/null; "

        async let acliResult = ShellCommandRunner.run(
            executableURL: zsh,
            arguments: ["-c", preamble + "command -v acli > /dev/null 2>&1 && acli --version 2>/dev/null | head -1 || echo NOT_INSTALLED"])
        async let jqResult = ShellCommandRunner.run(
            executableURL: zsh,
            arguments: ["-c", preamble + "command -v jq > /dev/null 2>&1 && jq --version 2>/dev/null || echo NOT_INSTALLED"])

        let (acliOut, jqOut) = (try? await acliResult, try? await jqResult)

        let acliStr = acliOut?.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) ?? "NOT_INSTALLED"
        self.acliStatus = acliStr == "NOT_INSTALLED" || acliStr.isEmpty ? .notInstalled : .installed(acliStr)

        let jqStr = jqOut?.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) ?? "NOT_INSTALLED"
        self.jqStatus = jqStr == "NOT_INSTALLED" || jqStr.isEmpty ? .notInstalled : .installed(jqStr)
    }

    private func installViaBrew(_ package: String) {
        let script = "tell application \"Terminal\" to do script \"brew install \(package)\""
        NSAppleScript(source: script)?.executeAndReturnError(nil)
    }

    private func checkHelperInstalled() async {
        let exists = FileManager.default.fileExists(atPath: NSString("~/.jira.zsh").expandingTildeInPath)
        guard exists else {
            self.helperStatus = .notInstalled
            return
        }
        let zshrcPath = NSString("~/.zshrc").expandingTildeInPath
        let zshrc = (try? String(contentsOfFile: zshrcPath, encoding: .utf8)) ?? ""
        self.helperStatus = zshrc.contains("source ~/.jira.zsh") ? .installed : .notInstalled
    }

    private func installShellHelpers() async {
        guard let scriptURL = AppResources.jiraHelperScriptURL() else { return }
        self.isInstallingHelper = true
        defer { self.isInstallingHelper = false }

        let dest = NSString("~/.jira.zsh").expandingTildeInPath
        do {
            if FileManager.default.fileExists(atPath: dest) {
                try FileManager.default.removeItem(atPath: dest)
            }
            try FileManager.default.copyItem(at: scriptURL, to: URL(fileURLWithPath: dest))

            let zshrcPath = NSString("~/.zshrc").expandingTildeInPath
            var zshrc = (try? String(contentsOfFile: zshrcPath, encoding: .utf8)) ?? ""
            if !zshrc.contains("source ~/.jira.zsh") {
                zshrc += "\nsource ~/.jira.zsh\n"
                try zshrc.write(toFile: zshrcPath, atomically: true, encoding: .utf8)
            }
            self.helperStatus = .installed
        } catch {
            self.helperStatus = .notInstalled
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
