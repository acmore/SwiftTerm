//
//  SelectionService.swift
//  iOS
//
//  Created by Miguel de Icaza on 3/5/20.
//  Copyright © 2020 Miguel de Icaza. All rights reserved.
//

import Foundation

/**
 * Tracks the selection state in the terminal, the selection is determined by the `active`
 * property, and if that is true, then the `start` and `end` represents offsets within
 * the terminal's buffer.  They are guaranteed to be ordered.
 */
class SelectionService: CustomDebugStringConvertible {
    var terminal: Terminal
    
    public init (terminal: Terminal)
    {
        self.terminal = terminal
        _active = false
        start = Position(col: 0, row: 0)
        end = Position(col: 0, row: 0)
        pivot = Position(col: 0, row: 0)
        hasSelectionRange = false
    }
    
    /**
     * Controls whether the selection is active or not.   Changing the value will invoke the `selectionChanged`
     * method on the terminal's delegate if the state changes.
     */
    var _active: Bool = false
    public var active: Bool {
        get {
            return _active
        }
        set(newValue) {
            if _active != newValue {
                _active = newValue
                terminal.tdel?.selectionChanged (source: terminal)
            }
            if active == false {
                pivot = nil
            }
        }
    }
    
    // This avoids the user visible cache
    func setActiveAndNotify () {
        _active = true
        terminal.tdel?.selectionChanged (source: terminal)
    }

    /**
     * Whether any range is selected
     */
    public private(set) var hasSelectionRange: Bool

    /**
     * Returns the selection starting point in buffer coordinates
     */
    public private(set) var start: Position {
        didSet {
          hasSelectionRange = start != end
        }
    }

    /**
     * Used to track the pivot point when selection in iOS-style selection
     */
    public var pivot: Position? 

    /**
     * Returns the selection ending point in buffer coordinates
     */
    public private(set) var end: Position {
        didSet {
          hasSelectionRange = start != end
        }
    }
    
    /// Re-anchors the selection after `lines` rows were trimmed off the front
    /// of the buffer, so it keeps covering the same text. A selection whose
    /// end scrolled out of the buffer entirely is cleared.
    func shiftForTrimmedLines(_ lines: Int) {
        guard active, lines > 0 else { return }
        if end.row - lines < 0 && start.row - lines < 0 {
            selectNone()
            return
        }
        start = Position(col: start.row - lines < 0 ? 0 : start.col, row: max(0, start.row - lines))
        end = Position(col: end.row - lines < 0 ? 0 : end.col, row: max(0, end.row - lines))
        if let p = pivot {
            pivot = Position(col: p.col, row: max(0, p.row - lines))
        }
        if let a = anchor {
            anchor = (Position(col: a.start.col, row: max(0, a.start.row - lines)),
                      Position(col: a.end.col, row: max(0, a.end.row - lines)))
        }
    }

    // MARK: Structured selection (touch hosts)

    /// Normalized selected buffer rows, nil when nothing is selected.
    public var selectedRows: ClosedRange<Int>? {
        guard active else { return nil }
        return min(start.row, end.row)...max(start.row, end.row)
    }

    private func isBlank(_ row: Int, in buffer: Buffer) -> Bool {
        guard row >= 0, row < buffer.lines.count else { return true }
        return buffer.lines[row].getTrimmedLength() == 0
    }

    /// Column of the first non-space cell, nil for a blank row.
    private func indent(_ row: Int, in buffer: Buffer) -> Int? {
        guard row >= 0, row < buffer.lines.count else { return nil }
        let text = buffer.lines[row].translateToString(trimRight: true)
        guard let first = text.firstIndex(where: { $0 != " " }) else { return nil }
        return text.distance(from: text.startIndex, to: first)
    }

    private func isWrappedContinuation(_ row: Int, in buffer: Buffer) -> Bool {
        guard row > 0, row < buffer.lines.count else { return false }
        return buffer.lines[row].isWrapped
    }

    /// Rows of the logical line containing `row` (soft-wrapped rows joined).
    public func logicalLineRange(containing row: Int, in buffer: Buffer) -> ClosedRange<Int> {
        let last = max(0, buffer.lines.count - 1)
        var top = min(max(0, row), last)
        while top > 0 && isWrappedContinuation(top, in: buffer) { top -= 1 }
        var bottom = min(max(0, row), last)
        while bottom < last && isWrappedContinuation(bottom + 1, in: buffer) { bottom += 1 }
        return top...bottom
    }

    /// The block around `row`:
    /// - a hanging-indent block — a head line at column 0 followed by
    ///   indented or blank lines (an agent reply, a tool call and its output,
    ///   a bullet list) — running until the next column-0 line;
    /// - otherwise the paragraph of non-blank lines around `row`.
    /// Trailing blank rows are never part of a block.
    public func blockRange(containing row: Int, in buffer: Buffer) -> ClosedRange<Int> {
        let last = max(0, buffer.lines.count - 1)
        let row = min(max(0, row), last)

        // Find the head: nearest row at or above `row` that starts at column 0.
        var head = row
        while head > 0 {
            if let i = indent(head, in: buffer), i == 0, !isWrappedContinuation(head, in: buffer) { break }
            head -= 1
        }
        var bottom = head
        var sawIndented = false
        var probe = head + 1
        while probe <= last {
            if isWrappedContinuation(probe, in: buffer) { bottom = probe; probe += 1; continue }
            if let i = indent(probe, in: buffer) {
                if i == 0 { break }
                sawIndented = true
                bottom = probe
            }
            probe += 1
        }
        if sawIndented && row >= head && row <= bottom && indent(head, in: buffer) == 0 {
            return head...bottom
        }

        // Paragraph fallback: contiguous non-blank rows around `row`.
        guard !isBlank(row, in: buffer) else { return logicalLineRange(containing: row, in: buffer) }
        var top = row
        while top > 0 && !isBlank(top - 1, in: buffer) { top -= 1 }
        var end = row
        while end < last && !isBlank(end + 1, in: buffer) { end += 1 }
        return top...end
    }

    /// The range the user started from (a word, line, block). Tap-to-extend
    /// grows the selection from it in whole rows and never loses it.
    public private(set) var anchor: (start: Position, end: Position)?

    /// Records the current range as the extension anchor.
    public func markAnchor() {
        guard active else { return }
        anchor = (start, end)
    }

    /// Selects whole rows `rows` and anchors there.
    public func selectRows(_ rows: ClosedRange<Int>) {
        start = Position(col: 0, row: rows.lowerBound)
        end = Position(col: terminal.cols - 1, row: rows.upperBound)
        pivot = start
        selectingRows = false
        selectionMode = .character
        anchor = (start, end)
        setActiveAndNotify()
    }

    /// Everything from the first to the last non-blank row of `buffer`.
    public func selectAllContent(in buffer: Buffer) {
        let last = max(0, buffer.lines.count - 1)
        var top = 0
        while top < last && isBlank(top, in: buffer) { top += 1 }
        var bottom = last
        while bottom > top && isBlank(bottom, in: buffer) { bottom -= 1 }
        selectRows(top...bottom)
    }

    /// Grows the selection from its anchor to cover `row` entirely: rows
    /// above the anchor start at column 0, rows below end at the last
    /// column. A row inside the anchor restores the anchor.
    public func extend(toRow row: Int) {
        guard active else { return }
        let a = anchor ?? (start, end)
        if anchor == nil { anchor = a }
        let (aStart, aEnd) = Position.compare(a.start, a.end) == .after ? (a.end, a.start) : (a.start, a.end)
        if row < aStart.row {
            start = Position(col: 0, row: row)
            end = aEnd
        } else if row > aEnd.row {
            start = aStart
            end = Position(col: terminal.cols - 1, row: row)
        } else {
            start = aStart
            end = aEnd
        }
        pivot = nil
    }

    /// True if the selection spans more than one line
    public var isMultiLine: Bool {
        return start.row != end.row
    }
    
    /**
     * Starts the selection from the specific screen-relative location
     */
    public func startSelection (row: Int, col: Int)
    {
        setSoftStart(row: row, col: col)
        selectionMode = .character
        setActiveAndNotify()
    }
        
    func clamp (_ buffer: Buffer, _ p: Position) -> Position {
        let maxRow = max(0, buffer.lines.count - 1)
        return Position(col: min(p.col, buffer.cols - 1), row: min(p.row, maxRow))
    }
    /**
     * Sets the selection, this is validated against the
     */
    public func setSelection (start: Position, end: Position) {
        let buffer = terminal.displayBuffer
        let sclamped = clamp (buffer, start)
        let eclamped = clamp (buffer, end)
        
        self.start = sclamped
        self.end = eclamped
        
        setActiveAndNotify()
    }

    /// Host ranges use boundaries between cells. In particular, `cols` is
    /// the valid exclusive boundary after the last glyph, not an invalid
    /// cell coordinate to clamp to `cols - 1`.
    func setSelectionBetweenBoundaries(start: Position, end: Position) {
        let buffer = terminal.displayBuffer
        func boundary(_ position: Position) -> Position {
            Position(col: max(0, min(position.col, buffer.cols)),
                     row: max(0, min(position.row, buffer.lines.count - 1)))
        }
        self.start = boundary(start)
        self.end = boundary(end)
        setActiveAndNotify()
    }
    
    /**
     * Starts selection, the range is determined by the last start position
     */
    public func startSelection ()
    {
        end = start
        selectingRows = false
        selectionMode = .character
        setActiveAndNotify()
    }
    
    /**
     * Sets the start and end positions but does not start selection
     * this lets us record the last position of mouse clicks so that
     * drag and shift+click operations know from where to start selection
     * from.
     *
     * The location is screen-relative
     */
    public func setSoftStart (row: Int, col: Int) {
        setSoftStart (bufferPosition: Position(col: col, row: row + terminal.displayBuffer.yDisp))
    }
    
    /**
     * Sets the start and end positions but does not start selection
     * this lets us record the last position of mouse clicks so that
     * drag and shift+click operations know from where to start selection
     * from.
     *
     * The locoation is buffer-relative
     */
    public func setSoftStart (bufferPosition: Position) {
        start = bufferPosition
        end = bufferPosition
        setActiveAndNotify()
    }
    
    /**
     * Extends the selection based on the user "shift" clicking. This has
     * slightly different semantics than a "drag" extension because we can
     * shift the start to be the last prior end point if the new extension
     * is before the current start point.
     *
     * The row is screen-relative
     */
    public func shiftExtend (row: Int, col: Int)
    {
        var newPos = Position  (col: col, row: row + terminal.displayBuffer.yDisp)
        if selectingRows {
            if Position.compare(start, newPos) == .before {
                newPos.col = terminal.cols - 1
            } else {
                newPos.col = 0
            }
        }
        print("SelectinRows=\(selectingRows)")
        shiftExtend (bufferPosition: newPos)
    }
    
    /**
     * Extends the selection based on the user "shift" clicking. This has
     * slightly different semantics than a "drag" extension because we can
     * shift the start to be the last prior end point if the new extension
     * is before the current start point.
     *
     * The bufferPosition is buffer-relative
     */
    public func shiftExtend (bufferPosition newEnd: Position) {
        var adjustedNewEnd = newEnd
        
        // If we're in word selection mode, extend to word boundaries
        if selectionMode == .word {
            let direction = Position.compare(newEnd, start) == .before ? -1 : 1
            adjustedNewEnd = extendToWordBoundary(position: newEnd, in: terminal.displayBuffer, direction: direction)
        }
        
        var shouldSwapStart = false
        if Position.compare (start, end) == .before {
            // start is before end, is the new end before Start
            if Position.compare (adjustedNewEnd, start) == .before {
                // yes, swap Start and End
                shouldSwapStart = true
            }
        } else if Position.compare (start, end) == .after {
            if Position.compare (adjustedNewEnd, start) == .after {
                // yes, swap Start and End
                shouldSwapStart = true
            }
        }
        if (shouldSwapStart) {
            start = end
        }
        end = adjustedNewEnd
        
        setActiveAndNotify()
    }
    
    /**
     * Implements the iOS selection around the pivot, that is, the handle that is being dragged
     * becomes the pivot point for start/end
     *
     * The row is screen-relative, for buffer relative use the `pivotExtend(bufferPosition:)` overload
     */
    public func pivotExtend (row: Int, col: Int) {
        let newPoint = Position  (col: col, row: row + terminal.displayBuffer.yDisp)

        return pivotExtend(bufferPosition: newPoint)
    }
    
    /**
     * Implements the iOS selection around the pivot, that is, the handle that is being dragged
     * becomes the pivot point for start/end
     *
     * The position is buffer-relative, for screen relative, use `pivotExtend(row:col:)`
     */
    public func pivotExtend (bufferPosition: Position) {
        guard let pivot = pivot else {
            return
        }
        
        var adjustedPosition = bufferPosition
        
        // If we're in word selection mode, extend to word boundaries
        if selectionMode == .word {
            let direction = Position.compare(bufferPosition, pivot) == .before ? -1 : 1
            adjustedPosition = extendToWordBoundary(position: bufferPosition, in: terminal.displayBuffer, direction: direction)
        }
        
        switch Position.compare (adjustedPosition, pivot) {
        case .after:
            start = pivot
            end = adjustedPosition
        case .before:
            start = adjustedPosition
            end = pivot
        case .equal:
            start = pivot
            end = pivot
        }
        
        setActiveAndNotify()
    }
    
    /**
     * Extends the selection by moving the end point to the new point.
     * The row is in screen coordinates
     */
    public func dragExtend (row: Int, col: Int)
    {
        dragExtend(bufferPosition: Position(col: col, row: row + terminal.displayBuffer.yDisp))
    }
    
    /**
     * Extends the selection by moving the end point to the new point.
     * The position is in buffer coordinates
     */
    public func dragExtend (bufferPosition: Position) {
        var adjustedEnd = bufferPosition
        
        // If we're in word selection mode, extend to word boundaries
        if selectionMode == .word {
            let direction = Position.compare(bufferPosition, start) == .before ? -1 : 1
            adjustedEnd = extendToWordBoundary(position: bufferPosition, in: terminal.displayBuffer, direction: direction)
        }
        
        end = adjustedEnd
        setActiveAndNotify()
    }
    
    /**
     * Selects the entire buffer and triggers the selection
     */
    public func selectAll ()
    {
        start = Position(col: 0, row: 0)
        end = Position(col: terminal.cols-1, row: terminal.displayBuffer.lines.maxLength - 1)
        setActiveAndNotify()
    }
    
    public var selectingRows: Bool = false
    
    /// Tracks the current selection mode to maintain consistency during extension
    public enum SelectionMode {
        case character
        case word
        case row
    }
    
    public var selectionMode: SelectionMode = .character
    
    /**
     * Selectss the specified row and triggers the selection
     */
    public func select(row: Int)
    {
        start = Position(col: 0, row: row)
        end = Position(col: terminal.cols-1, row: row)
        selectingRows = true
        selectionMode = .row
        setActiveAndNotify()
    }

    private func character (at position: Position, in buffer: Buffer) -> Character
    {
        let cell = buffer.getChar (atBufferRelative: position)
        return terminal.getCharacter (for: cell)
    }

    /**
     * Performs a simple "word" selection based on a function that determines inclussion into the group
     */
    func simpleScanSelection (from position: Position, in buffer: Buffer, includeFunc: (Character)-> Bool)
    {
        // Look backward
        var colScan = position.col
        var left = colScan
        while colScan >= 0 {
            let ch = character (at: Position (col: colScan, row: position.row), in: buffer)
            if !includeFunc (ch) {
                break
            }
            left = colScan
            colScan -= 1
        }
        
        // Look forward
        colScan = position.col
        var right = colScan
        let limit = terminal.cols
        while colScan < limit {
            let ch = character (at: Position (col: colScan, row: position.row), in: buffer)
            if !includeFunc (ch) {
                break
            }
            colScan += 1
            right = colScan
        }
        start = Position (col: left, row: position.row)
        end = Position(col: right, row: position.row)
    }
    
    /**
     * Performs a forward search for the `end` character, but this can extend across matching subexpressions
     * made of pais of parenthesis, braces and brackets.
     */
    func balancedSearchForward (from position: Position, in buffer: Buffer)
    {
        var startCol = position.col
        var wait: [Character] = []
        
        start = position
        
        let maxRow = buffer.rows + buffer.yDisp
        if position.row >= maxRow {
            return
        }
        for line in position.row..<maxRow {
            for col in startCol..<terminal.cols {
                let p =  Position(col: col, row: line)
                let ch = character (at: p, in: buffer)
                
                if ch == "(" {
                    wait.append (")")
                } else if ch == "[" {
                    wait.append ("]")
                } else if ch == "{" {
                    wait.append ("}")
                } else if let v = wait.last {
                    if v == ch {
                        wait.removeLast()
                        if wait.count == 0 {
                            end = Position(col: p.col+1, row: p.row)
                            return
                        }
                    }
                }
            }
            startCol = 0
        }
        start = position
        end = position
    }

    /**
     * Performs a forward search for the `end` character, but this can extend across matching subexpressions
     * made of pais of parenthesis, braces and brackets.
     */
    func balancedSearchBackward (from position: Position, in buffer: Buffer)
    {
        var startCol = position.col
        var wait: [Character] = []

        end = position
        
        for line in (0...position.row).reversed() {
            for col in (0...startCol).reversed() {
                let p =  Position(col: col, row: line)
                let ch = character (at: p, in: buffer)
                
                if ch == ")" {
                    wait.append ("(")
                } else if ch == "]" {
                    wait.append ("[")
                } else if ch == "}" {
                    wait.append ("{")
                } else if let v = wait.last {
                    if v == ch {
                        wait.removeLast()
                        if wait.count == 0 {
                            end = Position(col: end.col+1, row: end.row)
                            start = p
                            return
                        }
                    }
                }
            }
            startCol = terminal.cols-1
        }
        start = position
        end = position
    }

    let nullChar = Character(UnicodeScalar(0))
    
    /**
     * Extends a position to the nearest word boundary based on the character at that position
     */
    func extendToWordBoundary(position: Position, in buffer: Buffer, direction: Int) -> Position {
        let ch = character (at: position, in: buffer)
        var includeFunc: (Character) -> Bool
        
        switch ch {
        case Character(UnicodeScalar(0)):
            includeFunc = { ch in ch == Character(UnicodeScalar(0)) }
        case " ":
            includeFunc = { ch in ch == " " }
        case let ch where ch.isLetter || ch.isNumber:
            includeFunc = { ch in ch.isLetter || ch.isNumber || ch == "." || ch == "_" || ch == "-" }
        default:
            return position
        }
        
        var result = position
        if direction < 0 {
            // Extend backward
            var col = position.col
            while col >= 0 {
                let testCh = character (at: Position(col: col, row: position.row), in: buffer)
                if !includeFunc(testCh) {
                    break
                }
                result.col = col
                col -= 1
            }
        } else {
            // Extend forward
            var col = position.col
            while col < terminal.cols {
                let testCh = character (at: Position(col: col, row: position.row), in: buffer)
                if !includeFunc(testCh) {
                    break
                }
                col += 1
                result.col = col
            }
        }
        
        return result
    }
    /**
     * Implements the behavior to select the word at the specified position or an expression
     * which is a balanced set parenthesis, braces or brackets
     */
    public func selectWordOrExpression (at uncheckedPosition: Position, in buffer: Buffer)
    {
//        let position = Position(
//            col: max (min (uncheckedPosition.col, buffer.cols-1), 0),
//            row: max (min (uncheckedPosition.row, buffer.rows-1+buffer.yDisp), buffer.yDisp))
        let position = Position (col: (min (terminal.cols, max (uncheckedPosition.col, 0))),
                                 row: (max (uncheckedPosition.row, 0)))
        switch character (at: position, in: buffer) {
        case Character(UnicodeScalar(0)):
            simpleScanSelection (from: position, in: buffer) { ch in ch == nullChar }
        case " ":
            // Select all white space
            simpleScanSelection (from: position, in: buffer) { ch in ch == " " }
        case let ch where ch.isLetter || ch.isNumber:
            simpleScanSelection (from: position, in: buffer) { ch in ch.isLetter || ch.isNumber || ch == "." || ch == "_" || ch == "-" }
        case "{":
            fallthrough
        case "(":
            fallthrough
        case "[":
            balancedSearchForward (from: position, in: buffer)
        case ")":
            fallthrough
        case "]":
            fallthrough
        case "}":
            balancedSearchBackward(from: position, in: buffer)
        default:
            // For other characters, we just stop there
            start = position
            end = position
        }
        selectionMode = .word
        setActiveAndNotify()
    }
    
    /**
     * Clears the selection
     */
    public func selectNone ()
    {
        if active {
            active = false
            selectionMode = .character
        }
        anchor = nil
    }
    
    public func getSelectedText () -> String {
        let (min, max) = if Position.compare(start, end) == .before {
            (start, end)
        } else {
            (end, start)
        }
        let r = terminal.getDisplayText(start: min, end: max)
        return r
    }
    
    public var debugDescription: String {
        return "[Selection (active=\(active), start=\(start) end=\(end) hasSR=\(hasSelectionRange) pivot=\(pivot?.debugDescription ?? "nil")]"
    }
}
