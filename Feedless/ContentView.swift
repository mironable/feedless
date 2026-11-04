import SwiftUI
import UserNotifications

struct ContentView: View {
    @EnvironmentObject private var store: WebViewStore
    @EnvironmentObject private var settings: Settings
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false

    var body: some View {
        WebContainerView(store: store)
            .overlay(alignment: .bottomTrailing) {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 34, height: 34)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .padding(.trailing, 10)
                .padding(.bottom, 64)
                .accessibilityLabel("Feedless settings")
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .background(WindowAccessor { window in
                TouchIndicator.setEnabled(settings.showTouches, in: window)
            })
            .onReceive(NotificationCenter.default.publisher(for: AppDelegate.shakeNotification)) { _ in
                showSettings = true
            }
            .onReceive(NotificationCenter.default.publisher(for: AppDelegate.openURLNotification)) { note in
                if let url = note.object as? URL {
                    showSettings = false
                    store.webView.load(URLRequest(url: url))
                }
            }
            .onChange(of: scenePhase) { _, phase in
                guard InboxPoller.shared.isEnabled else { return }
                switch phase {
                case .background:
                    // Move the baseline past anything read in the app, then let iOS poll later.
                    Task { await InboxPoller.shared.poll(notify: false) }
                    BackgroundRefresh.schedule()
                case .active:
                    Task { try? await UNUserNotificationCenter.current().setBadgeCount(0) }
                default:
                    break
                }
            }
    }
}
