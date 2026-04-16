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
                Text(self.model.snapshot.auth.description)
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
                        Task { await self.model.switchAccount() }
                    }
                    .disabled(self.model.isPerformingAction)

                    Button("Logout") {
                        Task { await self.model.logout() }
                    }
                    .disabled(self.model.isPerformingAction)
                } else {
                    Button("Login") {
                        Task { await self.model.login() }
                    }
                    .disabled(self.model.isPerformingAction)
                }
            }

            Section {
                Button("Settings…") {
                    Self.openSettingsWindow()
                }

                Button("Quit JiraBar") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .task {
            await self.model.refreshIfNeededForMenuOpen()
        }
    }

    @MainActor private static func openSettingsWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            for window in NSApp.windows {
                guard window.title.contains("Settings") else { continue }
                window.collectionBehavior.insert(.moveToActiveSpace)
                window.orderFrontRegardless()
                window.makeKeyAndOrderFront(nil)

                NotificationCenter.default.addObserver(
                    forName: NSWindow.willCloseNotification,
                    object: window,
                    queue: .main
                ) { _ in
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
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

            Menu("Move to") {
                ForEach(JiraWorkflowStatus.allCases) { status in
                    Button(status.label) {
                        Task { await self.model.move(self.ticket, to: status) }
                    }
                    .disabled(self.model.isPerformingAction)
                }
            }
        }
    }
}
