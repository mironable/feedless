import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: Settings
    @EnvironmentObject private var store: WebViewStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Hide") {
                    ForEach(store.rules.categories) { category in
                        Toggle(isOn: binding(for: category.id)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(category.title)
                                Text(category.detail).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Home feed") {
                    Picker("Feed", selection: $settings.feedID) {
                        ForEach(store.rules.feeds) { feed in
                            Text(feed.title).tag(feed.id)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Debug") {
                    Toggle("Show touches", isOn: $settings.showTouches)
                }

                Section {
                    Button("Reset session", role: .destructive) { confirmReset = true }
                } footer: {
                    Text("Signs you out and clears cookies, cache and site data for \(store.rules.name).")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
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
