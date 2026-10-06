#if os(macOS)
import AppKit
import Testing

@testable import SwiftTerm

/// `clearsSelectionOnContentChange` and the wheel bytes `handleScroll` sends:
/// host-facing behaviour of the view that Sigmux relies on.
@MainActor
struct TerminalViewSelectionPolicyTests {
    private final class Delegate: TerminalViewDelegate {
        var writes: [[UInt8]] = []
        func send(source: TerminalView, data: ArraySlice<UInt8>) { writes.append(Array(data)) }
        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func scrolled(source: TerminalView, position: Double) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
    }

    private func view() -> TerminalView {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        view.feed(text: "line one\r\nline two\r\n")
        view.selectAll(nil)
        #expect(view.selectionActive)
        return view
    }

    @Test func selectedContentChangeClearsByDefault() {
        let view = view()
        #expect(view.clearsSelectionOnContentChange)
        view.feed(text: "\u{1b}[1;1Hrewritten")
        #expect(!view.selectionActive)
    }

    @Test func stickySelectionSurvivesSelectedContentChange() {
        let view = view()
        view.clearsSelectionOnContentChange = false
        view.feed(text: "\u{1b}[s\u{1b}[1;30H12:00\u{1b}[u")
        view.feed(text: "\u{1b}[1;1Hrewritten")
        view.feed(text: "spinner tick\r\n")
        #expect(view.selectionActive)
        #expect(view.getSelection()?.contains("rewritten") == true, "reads the live rows")
    }

    @Test func stickySelectionStillClearsOnBufferSwitch() {
        let view = view()
        view.clearsSelectionOnContentChange = false
        view.feed(text: "\u{1b}[?1049h")
        #expect(!view.selectionActive)
    }

    @Test func handleScrollDeliversWheelBytesBeforeReturning() {
        let view = TerminalView(frame: .zero)
        let delegate = Delegate()
        view.terminalDelegate = delegate
        view.resize(cols: 80, rows: 24)
        view.feed(text: "\u{1b}[?1000h\u{1b}[?1006h")

        let action = view.handleScroll(lines: 2, x: 12, y: 5)

        #expect(action == .mouseWheel(lines: 2))
        #expect(delegate.writes == [Array("\u{1b}[<64;13;6M\u{1b}[<64;13;6M".utf8)])
    }
}
#endif
