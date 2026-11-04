import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: Settings
    @EnvironmentObject private var store: WebViewStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmReset = false
    @State private var exportedFile: ExportedFile?
    @State private var pollSummary = InboxPoller.shared.lastSummary
    @State private var polling = false

    private struct ExportedFile: Identifiable {
        let url: URL
        var id: String { url.path }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(store.rules.categories) { category in
                        Toggle(isOn: binding(for: category.id)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(category.title)
                                Text(category.detail).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("What Feedless hides")
                } footer: {
                    Text("Changes apply at once, without reloading the page.")
                }

                Section("Home feed") {
                    Picker("Feed", selection: $settings.feedID) {
                        ForEach(store.rules.feeds) { feed in
                            Text(feed.title).tag(feed.id)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Toggle("New message alerts", isOn: $settings.dmNotifications)
                        .onChange(of: settings.dmNotifications) { _, enabled in
                            Task {
                                if enabled {
                                    if await InboxPoller.shared.requestAuthorization() {
                                        await InboxPoller.shared.poll(notify: false)
                                        BackgroundRefresh.schedule()
                                    } else {
                                        settings.dmNotifications = false
                                    }
                                } else {
                                    BackgroundRefresh.cancel()
                                }
                                pollSummary = InboxPoller.shared.lastSummary
                            }
                        }
                    Button(polling ? "Polling…" : "Poll now") {
                        polling = true
                        Task {
                            await InboxPoller.shared.poll(notify: true)
                            pollSummary = InboxPoller.shared.lastSummary
                            polling = false
                        }
                    }
                    .disabled(polling || !settings.dmNotifications)
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Instagram cannot push to Feedless. The app re-checks Instagram's unread-message count in the background a few times an hour, when iOS allows it, and alerts you when it grows. Last check: \(pollSummary)")
                }

                Section("Debug") {
                    Toggle("Show touches", isOn: $settings.showTouches)
                    Button("Export page HTML") {
                        Task {
                            if let url = try? await store.exportPageHTML() { exportedFile = ExportedFile(url: url) }
                        }
                    }
                    Button("Export network log") {
                        Task {
                            if let url = try? await store.exportNetworkLog() { exportedFile = ExportedFile(url: url) }
                        }
                    }
                }

                Section {
                    Button("Reset session", role: .destructive) { confirmReset = true }
                } footer: {
                    Text("Signs you out and clears cookies, cache and site data for \(store.rules.name). Tap the gear in Instagram's header or shake the phone to open this screen.")
                }
            }
            .navigationTitle("Feedless")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $exportedFile) { file in
                ShareSheet(items: [file.url])
            }
            .confirmationDialog("Reset session?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset and sign out", role: .destructive) {
                    Task {
                        await store.resetSession()
                        dismiss()
                    }
                }
            }
        }
    }

    private func binding(for categoryID: String) -> Binding<Bool> {
        Binding(
            get: { settings.isEnabled(categoryID) },
            set: { settings.setEnabled($0, for: categoryID) }
        )
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
