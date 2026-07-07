//
//  ScreenTitleEscapeTests.swift
//
//  screen/tmux-style title escape: ESC k <title> ESC \ (ST).
//  Shells inside tmux (TERM=screen*) emit it via preexec/precmd title
//  hooks; the payload must be consumed, never rendered as text.
//
#if os(macOS)
import Foundation
import Testing

@testable import SwiftTerm

final class ScreenTitleEscapeTests {
    private let esc = "\u{1b}"

    private func visibleText(_ t: Terminal, row: Int) -> String {
        var line = ""
        for col in 0..<t.cols {
            let ch = t.getCharacter(col: col, row: row) ?? " "
            line.append(ch == "\u{0}" ? " " : ch)
        }
        return line.trimmingCharacters(in: .whitespaces)
    }

    @Test func screenTitlePayloadIsNotRendered() {
        let h = HeadlessTerminal(queue: SwiftTermTests.queue) { _ in }
        let t = h.terminal!

        // zsh-style: set title to the running command, then the command output.
        t.feed(text: "\(esc)kecho\(esc)\\1\r\n")

        #expect(visibleText(t, row: 0) == "1")
    }

    @Test func screenTitleTerminatedByBelIsNotRendered() {
        let h = HeadlessTerminal(queue: SwiftTermTests.queue) { _ in }
        let t = h.terminal!

        t.feed(text: "\(esc)ktitle text\u{7}ok\r\n")

        #expect(visibleText(t, row: 0) == "ok")
    }

    @Test func textAfterTitleAcrossChunksRendersNormally() {
        let h = HeadlessTerminal(queue: SwiftTermTests.queue) { _ in }
        let t = h.terminal!

        // Split mid-payload and mid-terminator like tmux %output chunking can.
        t.feed(text: "\(esc)kec")
        t.feed(text: "ho\(esc)")
        t.feed(text: "\\done\r\n")

        #expect(visibleText(t, row: 0) == "done")
    }
}
#endif
