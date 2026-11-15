import SwiftUI
import UIKit

/// Touch on the picture, in UIKit so one surface can tell a tap from a two-finger tap,
/// a vertical swipe from a pinch, and hand over the finger's velocity.
struct PictureGestures: UIViewRepresentable {
    var onTap: () -> Void
    var onTwoFingerTap: () -> Void
    /// Vertical finger travel while dragging (points, up is negative).
    var onDrag: (CGFloat) -> Void
    /// Released: travel and velocity (points per second, up is negative).
    var onRelease: (CGFloat, CGFloat) -> Void
    /// Pinched out (true) or in (false).
    var onPinch: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        let c = context.coordinator
        let tap = UITapGestureRecognizer(target: c, action: #selector(Coordinator.tap))
        let two = UITapGestureRecognizer(target: c, action: #selector(Coordinator.twoFingerTap))
        two.numberOfTouchesRequired = 2
        tap.require(toFail: two)
        let pan = UIPanGestureRecognizer(target: c, action: #selector(Coordinator.pan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = c
        let pinch = UIPinchGestureRecognizer(target: c, action: #selector(Coordinator.pinch(_:)))
        [tap, two, pan, pinch].forEach(v.addGestureRecognizer)
        return v
    }

    func updateUIView(_ v: UIView, context: Context) { context.coordinator.parent = self }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: PictureGestures?

        @objc func tap() { parent?.onTap() }
        @objc func twoFingerTap() { parent?.onTwoFingerTap() }

        @objc func pan(_ g: UIPanGestureRecognizer) {
            let dy = g.translation(in: g.view).y
            switch g.state {
            case .changed: parent?.onDrag(dy)
            case .ended, .cancelled: parent?.onRelease(dy, g.velocity(in: g.view).y)
            default: break
            }
        }

        @objc func pinch(_ g: UIPinchGestureRecognizer) {
            guard g.state == .ended else { return }
            if g.scale > 1.08 { parent?.onPinch(true) } else if g.scale < 0.92 { parent?.onPinch(false) }
        }

        /// Only mostly-vertical drags change channel; sideways ones are left alone.
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard let pan = g as? UIPanGestureRecognizer else { return true }
            let v = pan.velocity(in: pan.view)
            return abs(v.y) > abs(v.x) * 1.2
        }
    }
}
