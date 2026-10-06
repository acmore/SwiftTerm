#if os(iOS)
import UIKit
import XCTest
@testable import SwiftTerm

@MainActor
final class IOSSelectionMenuTests: XCTestCase {
    @available(iOS 16.0, *)
    func testHostBuiltMenuReplacesTheDefaultAndSeesTheSuggestions() {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        view.feed(text: "hello world")
        view.selectAll(nil)
        let interaction = UIEditMenuInteraction(delegate: view)
        let configuration = UIEditMenuConfiguration(identifier: nil, sourcePoint: .zero)
        let suggestion = UIAction(title: "Look Up") { _ in }

        var received: [UIMenuElement]?
        view.editMenuBuilder = { suggested in
            received = suggested
            return UIMenu(children: [UIAction(title: "Host copy") { _ in }])
        }
        let built = view.editMenuInteraction(interaction, menuFor: configuration, suggestedActions: [suggestion])
        XCTAssertEqual(built?.children.map(\.title), ["Host copy"])
        XCTAssertEqual(received?.map(\.title), ["Look Up"])

        view.editMenuBuilder = nil
        let fallback = view.editMenuInteraction(interaction, menuFor: configuration, suggestedActions: [])
        XCTAssertEqual(fallback?.children.first?.title, "Copy", "without a builder the library menu is unchanged")
    }

    func testHostSelectRangeAnchorsForLineAndBlock() {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        view.feed(text: "first row here\r\nsecond row\r\n\r\nafter blank")
        view.select(from: Position(col: 7, row: 1), to: Position(col: 10, row: 1))
        XCTAssertEqual(view.selectedText, "row")
        XCTAssertEqual(view.selectedRowRange, 1...1)
        view.selectLineAtAnchor()
        XCTAssertEqual(view.selectedText, "second row", "line selection works around the host-set anchor")
        view.selectBlockAtAnchor()
        XCTAssertEqual(view.selectedRowRange, 0...1)
    }

    func testPresentAndDismissFollowTheSelection() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        window.addSubview(view)
        defer { window.isHidden = true }
        view.feed(text: "hello world")
        view.presentSelectionMenu()
        XCTAssertEqual(view.lastLongSelectRegion, .zero, "nothing to show without a selection")
        view.selectAll(nil)
        view.presentSelectionMenu()
        XCTAssertNotEqual(view.lastLongSelectRegion, .zero)
        view.dismissSelectionMenu()
        XCTAssertTrue(view.selectionActive, "dismissing the menu keeps the selection")
    }

    func testHostRangeIncludesTheLastCellWithoutSelectingTheNextRow() {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        let cols = view.getTerminal().cols
        let text = String(repeating: "x", count: cols - 2) + "中"
        view.feed(text: text + "\r\nnext row")
        view.select(from: Position(col: 0, row: 0), to: Position(col: cols, row: 0))
        XCTAssertEqual(view.selectedText, text)
        XCTAssertEqual(view.selectedRowRange, 0...0)
        view.select(from: Position(col: cols - 2, row: 0), to: Position(col: cols, row: 0))
        XCTAssertEqual(view.selectedText, "中")
    }
}
#endif
