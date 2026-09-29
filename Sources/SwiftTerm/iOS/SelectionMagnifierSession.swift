#if os(iOS) || os(visionOS)
import UIKit

/// Keeps the iOS 17 loupe API out of TerminalView's iOS 14 stored layout.
/// Closures also let gesture tests record the real sample geometry without
/// depending on UIKit's private loupe hierarchy.
@MainActor
struct SelectionMagnifierSession {
    let move: (CGPoint, CGRect) -> Void
    let invalidate: () -> Void

    static func begin(at point: CGPoint, in view: UIView) -> Self? {
#if os(iOS)
        if #available(iOS 17.0, *),
           let session = UITextLoupeSession.begin(at: point, fromSelectionWidgetView: nil, in: view) {
            return Self(move: { point, caret in
                session.move(to: point, withCaretRect: caret, trackingCaret: true)
            }, invalidate: { session.invalidate() })
        }
#endif
        return nil
    }
}
#endif
