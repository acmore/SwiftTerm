//
//  RenderedLineCache.swift
//  SwiftTerm
//
//  Rows shaped through CoreText, kept by cell content so a redraw only
//  shapes the rows whose cells changed.
//

#if os(macOS) || os(iOS) || os(visionOS)
import Foundation
import CoreText

/// One segment of a row after shaping: the CTLine and its glyph runs.
struct PreparedLineSegment {
    let segment: ViewLineSegment
    let ctLine: CTLine
    let runs: [CTRun]
}

/// Rows shaped through CoreText, keyed by their cells.
///
/// On iOS every terminal update invalidates the whole view, and a TUI frame
/// leaves most rows as they were; shaping those rows again was the largest
/// cost of a repaint. Rows are matched by content rather than identity, so
/// the copies a synchronized-output snapshot makes, and rows that scrolled
/// to another position, still hit.
final class RenderedLineCache {
    /// View state that changes how cells shape. When it changes, every entry goes.
    struct Environment: Equatable {
        var cols: Int
        var customBlockGlyphs: Bool
        var useBrightColors: Bool
        var linkHighlightMode: LinkHighlightMode
        var commandActive: Bool
    }

    final class Entry {
        let cells: [CharData]
        /// `images` is nil here; the caller takes images from the live line.
        let line: ViewLineInfo
        let prepared: [PreparedLineSegment]
        var lastUsed: Int

        init(cells: [CharData], line: ViewLineInfo, prepared: [PreparedLineSegment], lastUsed: Int) {
            self.cells = cells
            self.line = line
            self.prepared = prepared
            self.lastUsed = lastUsed
        }
    }

    private var entries: [Int: [Entry]] = [:]
    private var environment: Environment?
    private(set) var count = 0
    private(set) var drawSerial = 0
    private(set) var hits = 0
    private(set) var misses = 0

    /// Starts a draw; drops the cache when the environment changed.
    func beginDraw(_ environment: Environment) {
        if self.environment != environment {
            removeAll()
            self.environment = environment
        }
        drawSerial += 1
    }

    func lookup(line: BufferLine, cols: Int) -> Entry? {
        let key = Self.key(line: line, cols: cols)
        guard let bucket = entries[key],
              let entry = bucket.first(where: { line.cellsEqual($0.cells, cols: cols) }) else {
            misses += 1
            return nil
        }
        entry.lastUsed = drawSerial
        hits += 1
        return entry
    }

    @discardableResult
    func store(line: BufferLine, cols: Int, info: ViewLineInfo, prepared: [PreparedLineSegment]) -> Entry {
        var stored = info
        stored.images = nil
        let entry = Entry(cells: line.cells(cols: cols), line: stored, prepared: prepared, lastUsed: drawSerial)
        entries[Self.key(line: line, cols: cols), default: []].append(entry)
        count += 1
        return entry
    }

    /// Ends a draw. Once the cache outgrows `capacity` rows, entries not
    /// used by this draw or the one before are dropped.
    func endDraw(capacity: Int) {
        guard count > capacity else {
            return
        }
        let keepFrom = drawSerial - 1
        for (key, bucket) in entries {
            let kept = bucket.filter { $0.lastUsed >= keepFrom }
            if kept.count != bucket.count {
                count -= bucket.count - kept.count
                entries[key] = kept.isEmpty ? nil : kept
            }
        }
    }

    func removeAll() {
        entries = [:]
        count = 0
    }

    private static func key(line: BufferLine, cols: Int) -> Int {
        var hasher = Hasher()
        line.hashCells(cols: cols, into: &hasher)
        return hasher.finalize()
    }
}
#endif
