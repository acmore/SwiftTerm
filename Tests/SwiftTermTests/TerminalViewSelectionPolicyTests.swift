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

    @Test func frozenDisplayKeepsSelectionAcrossSeparateFeedTransactions() {
        for clearsOnChange in [false, true] {
            let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
            view.withTerminal { $0.freezesDisplayBufferDuringSynchronizedOutput = true }
            view.clearsSelectionOnContentChange = clearsOnChange
            view.feed(text: "\u{1b}[?1049hsrc/original.swift:8")
            view.selectAll(nil)
            view.feed(text: "\u{1b}[?2026h\u{1b}[H\u{1b}[2Ksrc/replaced.swift:9")
            #expect(view.selectionActive)
            #expect(view.getSelection()?.contains("original") == true)
            view.feed(text: "\u{1b}[?2026l")
            #expect(view.selectionActive == !clearsOnChange)
            if !clearsOnChange {
                #expect(view.getSelection()?.contains("replaced") == true)
            }
        }
    }

    @Test func frozenScrollbackTrimIsNotAppliedTwiceByFeedTransaction() {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        view.resize(cols: 40, rows: 5)
        view.withTerminal {
            $0.changeHistorySize(2)
            $0.freezesDisplayBufferDuringSynchronizedOutput = true
        }
        view.clearsSelectionOnContentChange = false
        view.feed(text: "0\r\n1\r\n2\r\n3\r\n4\r\n5\r\n6")
        view.withTerminal { _ in view.selection.selectRows(4...4) }
        view.feed(text: "\u{1b}[?2026h\r\n7\r\n8")
        #expect(view.withTerminal { _ in view.selection.selectedRows } == 4...4)
        view.feed(text: "\u{1b}[?2026l")
        #expect(view.withTerminal { _ in view.selection.selectedRows } == 2...2)
        #expect(view.getSelection()?.trimmingCharacters(in: .whitespacesAndNewlines) == "4")
        view.feed(text: "\r\n9")
        #expect(view.withTerminal { _ in view.selection.selectedRows } == 1...1)
        #expect(view.getSelection()?.trimmingCharacters(in: .whitespacesAndNewlines) == "4")
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
