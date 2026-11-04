import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: WebViewStore
    @EnvironmentObject private var settings: Settings
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
    }
}
