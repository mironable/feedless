import UIKit

/// Draws a circle under every finger so screen recordings show taps. Off by default.
enum TouchIndicator {
    static func setEnabled(_ enabled: Bool, in window: UIWindow) {
        let existing = window.gestureRecognizers?.compactMap { $0 as? TouchIndicatorRecognizer }.first
        if enabled, existing == nil {
            let overlay = TouchOverlayView(frame: window.bounds)
            overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            window.addSubview(overlay)
            window.addGestureRecognizer(TouchIndicatorRecognizer(overlay: overlay))
        } else if !enabled, let existing {
            existing.overlay.removeFromSuperview()
            window.removeGestureRecognizer(existing)
        }
    }
}

final class TouchIndicatorRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    let overlay: TouchOverlayView

    init(overlay: TouchOverlayView) {
        self.overlay = overlay
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) { overlay.update(event.allTouches ?? touches) }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) { overlay.update(event.allTouches ?? touches) }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { overlay.update(event.allTouches ?? touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { overlay.update(event.allTouches ?? touches) }
}

final class TouchOverlayView: UIView {
    private var circles: [ObjectIdentifier: UIView] = [:]
    private let diameter: CGFloat = 44

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(_ touches: Set<UITouch>) {
        superview?.bringSubviewToFront(self)
        var live = Set<ObjectIdentifier>()
        for touch in touches {
            let id = ObjectIdentifier(touch)
            let point = touch.location(in: self)
            switch touch.phase {
            case .began, .moved, .stationary, .regionEntered, .regionMoved, .regionExited:
                live.insert(id)
                let circle = circles[id] ?? makeCircle(id)
                circle.center = point
            default:
                fade(id)
            }
        }
        for id in circles.keys where !live.contains(id) { fade(id) }
    }

    private func makeCircle(_ id: ObjectIdentifier) -> UIView {
        let circle = UIView(frame: CGRect(x: 0, y: 0, width: diameter, height: diameter))
        circle.layer.cornerRadius = diameter / 2
        circle.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.35)
        circle.layer.borderColor = UIColor.systemBlue.withAlphaComponent(0.9).cgColor
        circle.layer.borderWidth = 2
        addSubview(circle)
        circles[id] = circle
        return circle
    }

    private func fade(_ id: ObjectIdentifier) {
        guard let circle = circles.removeValue(forKey: id) else { return }
        UIView.animate(withDuration: 0.25, animations: { circle.alpha = 0; circle.transform = CGAffineTransform(scaleX: 1.6, y: 1.6) }) { _ in
            circle.removeFromSuperview()
        }
    }
}
