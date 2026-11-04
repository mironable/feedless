import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: WebViewStore
    @EnvironmentObject private var settings: Settings
    @State private var showSettings = false

    var body: some View {
        WebContainerView(store: store)
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .background(WindowAccessor { window in
                TouchIndicator.setEnabled(settings.showTouches, in: window)
            })
            .onReceive(NotificationCenter.default.publisher(for: AppDelegate.shakeNotification)) { _ in
                showSettings = true
            }
    }
}
