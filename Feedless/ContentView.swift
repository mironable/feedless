import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: WebViewStore
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            WebContainerView(store: store)
            Divider()
            HStack(spacing: 28) {
                Button { store.webView.goBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(!store.canGoBack)
                Button { store.loadHome() } label: { Image(systemName: "house") }
                Button { store.loadSearch() } label: { Image(systemName: "magnifyingglass") }
                Spacer()
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
            }
            .font(.title3)
            .padding(.horizontal, 20)
            .frame(height: 44)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
}
