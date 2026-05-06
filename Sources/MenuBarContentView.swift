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
                        Text("No stories assigned to you in the current sprint.")
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

            Section("Bugs") {
                if self.model.snapshot.auth.authorized {
                    if self.model.visibleBugs.isEmpty {
                        Text("No open bugs assigned to you.")
                    } else {
                        ForEach(self.model.visibleBugs) { ticket in
                            TicketRowMenu(ticket: ticket, model: self.model)
                        }
                        if self.model.snapshot.bugs.count > self.model.visibleBugs.count {
                            Text("+\(self.model.snapshot.bugs.count - self.model.visibleBugs.count) more bugs")
                        }
                    }
                } else {
                    Text("Login to load your bugs.")
                }
            }

            Section("Task + Subtask") {
                if self.model.snapshot.auth.authorized {
                    if self.model.visibleTasks.isEmpty {
                        Text("No open tasks assigned to you.")
                    } else {
                        ForEach(self.model.visibleTasks) { ticket in
                            TicketRowMenu(ticket: ticket, model: self.model)
                        }
                        if self.model.snapshot.tasks.count > self.model.visibleTasks.count {
                            Text("+\(self.model.snapshot.tasks.count - self.model.visibleTasks.count) more tasks")
                        }
                    }
                } else {
                    Text("Login to load your tasks.")
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
        window.level = .floating
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

        DispatchQueue.main.async {
            guard let screen = NSScreen.main else { return }
            let visible = screen.visibleFrame
            let size = window.frame.size
            let x = visible.maxX - size.width - 16
            let y = visible.maxY - size.height - 16
            window.setFrameOrigin(NSPoint(x: x, y: y))
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
            .disabled(self.model.isPerformingAction || self.model.actingOnTicketKey == self.ticket.key)

            Button("Assign to Me") {
                Task { await self.model.assignToMe(self.ticket) }
            }
            .disabled(self.model.isPerformingAction || self.model.actingOnTicketKey == self.ticket.key)

            Divider()
            Button("Next Status") {
                Task { await self.model.moveForward(self.ticket) }
            }
            .disabled(self.model.isPerformingAction || self.model.actingOnTicketKey == self.ticket.key)
            Button("Previous Status") {
                Task { await self.model.moveBackward(self.ticket) }
            }
            .disabled(self.model.isPerformingAction || self.model.actingOnTicketKey == self.ticket.key)

            let statuses = self.model.projectStatuses
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
