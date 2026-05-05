import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var model: JiraBarModel

    var body: some View {
        Group {
            Section {
                Text(self.model.snapshot.boardName.map { "\($0) JiraBar" } ?? "JiraBar")
                if let accountEmail = self.model.snapshot.accountEmail, !accountEmail.isEmpty {
                    Text(accountEmail)
                }
                if !self.model.snapshot.site.isEmpty {
                    Text(self.model.snapshot.site)
                } else if !self.model.preferredSite.isEmpty {
                    Text("Configured: \(self.model.preferredSite)")
                }
            }

            Section("Status") {
                Text("Last refresh: \(self.model.lastRefreshDescription)")
                if let message = self.model.lastActionMessage, !message.isEmpty {
                    Text(message)
                }
                if let error = self.model.lastErrorMessage, !error.isEmpty {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }

            Section("Stories") {
                if self.model.snapshot.auth.authorized {
                    if self.model.visibleStories.isEmpty {
                        Text("No parent stories in the current sprint.")
                    } else {
                        ForEach(self.model.visibleStories) { ticket in
                            TicketRowMenu(ticket: ticket, model: self.model)
                        }
                        if self.model.snapshot.stories.count > self.model.visibleStories.count {
                            Text("+\(self.model.snapshot.stories.count - self.model.visibleStories.count) more stories")
                        }
                    }
                } else {
                    Text("Login to load sprint stories.")
                }
            }

            Section("My Not Done") {
                if self.model.snapshot.auth.authorized {
                    if self.model.visibleTickets.isEmpty {
                        Text("No not-done tickets assigned to you.")
                    } else {
                        ForEach(self.model.visibleTickets) { ticket in
                            TicketRowMenu(ticket: ticket, model: self.model)
                        }
                        if self.model.snapshot.tickets.count > self.model.visibleTickets.count {
                            Text("+\(self.model.snapshot.tickets.count - self.model.visibleTickets.count) more tickets")
                        }
                    }
                } else {
                    Text("Login to load your current sprint work.")
                }
            }

            Section("Actions") {
                Button("Refresh Now") {
                    Task { await self.model.refresh(force: true) }
                }
                .disabled(self.model.isRefreshing || self.model.isPerformingAction)

                if self.model.snapshot.auth.authorized {
                    Button("Switch Account") {
                        self.model.switchAccount()
                    }
                    .disabled(self.model.isPerformingAction)

                    Button("Logout") {
                        self.model.logout()
                    }
                    .disabled(self.model.isPerformingAction)
                } else {
                    Button("Login") {
                        self.model.login()
                    }
                    .disabled(self.model.isPerformingAction)
                }
            }

            Section {
                Button("Settings…") {
                    Self.openSettingsWindow(model: self.model)
                }

                Button("Quit JiraBar") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .task {
            await self.model.refresh(force: false)
        }
    }

    private static var settingsWindow: NSWindow?

    @MainActor private static func openSettingsWindow(model: JiraBarModel) {
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(rootView: SettingsView(model: model))
        hosting.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: hosting)
        window.title = "JiraBar Settings"
        window.styleMask = [.titled, .closable]
        window.collectionBehavior = [.moveToActiveSpace]
        window.center()
        settingsWindow = window

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { _ in
            Task { @MainActor in
                NSApp.setActivationPolicy(.accessory)
                settingsWindow = nil
            }
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

private struct TicketRowMenu: View {
    let ticket: JiraTicket
    @ObservedObject var model: JiraBarModel

    var body: some View {
        Menu(self.ticket.menuTitle) {
            Text(self.ticket.statusLine)
            Divider()

            Button("Open in Jira") {
                Task { await self.model.openInBrowser(self.ticket) }
            }
            .disabled(self.model.isPerformingAction)

            Button("Assign to Me") {
                Task { await self.model.assignToMe(self.ticket) }
            }
            .disabled(self.model.isPerformingAction)

            Divider()
            Button("Next Status") {
                Task { await self.model.moveForward(self.ticket) }
            }
            .disabled(self.model.isPerformingAction)
            Button("Previous Status") {
                Task { await self.model.moveBackward(self.ticket) }
            }
            .disabled(self.model.isPerformingAction)

            let statuses = self.model.statuses(for: self.ticket)
            if !statuses.isEmpty {
                Menu("Move") {
                    ForEach(statuses, id: \.self) { statusName in
                        let isCurrent = statusName.caseInsensitiveCompare(self.ticket.status) == .orderedSame
                        Button(isCurrent ? "✓ \(statusName)" : statusName) {
                            Task { await self.model.move(self.ticket, to: statusName) }
                        }
                        .disabled(self.model.isPerformingAction || isCurrent)
                    }
                }
            }
        }
    }
}
