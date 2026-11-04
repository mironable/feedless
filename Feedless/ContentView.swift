import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: WebViewStore

    var body: some View {
        VStack(spacing: 0) {
            WebContainerView(store: store)
            Divider()
            HStack {
                Button { store.webView.goBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(!store.canGoBack)
                Button { store.loadHome() } label: { Image(systemName: "house") }
                Spacer()
            }
            .font(.title3)
            .padding(.horizontal, 20)
            .frame(height: 44)
        }
    }
}
