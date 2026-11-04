import SwiftUI

/// Hands the hosting UIWindow to SwiftUI code once it exists.
struct WindowAccessor: UIViewRepresentable {
    let onWindow: (UIWindow) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isHidden = true
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            if let window = uiView.window { onWindow(window) }
        }
    }
}
