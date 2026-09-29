#if os(iOS) || os(visionOS)
import UIKit

/// UIPan's translation excludes its recognition slop. Keep the actual
/// touch-down point so a short drag does not lose its first ~10 points.
class SelectionPanGestureRecognizer: UIPanGestureRecognizer {
    var touchDownLocation: CGPoint?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if touchDownLocation == nil, let view = view as? TerminalView, let touch = touches.first {
            let point = touch.location(in: view)
            touchDownLocation = point
            // Fail before the long-press timeout when the user touches text
            // away from a handle, so they can start a fresh word selection.
            if !view.isNearSelectionHandle(point) {
                state = .failed
                return
            }
        }
        super.touchesBegan(touches, with: event)
    }

    override func reset() {
        super.reset()
        touchDownLocation = nil
    }
}
#endif
