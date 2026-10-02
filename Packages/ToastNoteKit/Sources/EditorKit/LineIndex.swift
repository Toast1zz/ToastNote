import Foundation
import Markdown

/// Maps swift-markdown source locations (1-based line, 1-based UTF-8 byte column) to UTF-16 offsets,
/// which is what NSTextView uses.
public struct LineIndex: Sendable {
    private struct Line: Sendable {
        let utf16Start: Int
        let utf16Length: Int
        let text: Substring
        /// ASCII lines map columns to offsets one to one, which avoids walking scalars.
        let isASCII: Bool
    }

    private let lines: [Line]
    private let totalLength: Int

    public init(_ text: String) {
        var result: [Line] = []
        var start = 0
        for piece in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let length = piece.utf16.count
            result.append(Line(utf16Start: start, utf16Length: length, text: piece, isASCII: piece.utf8.count == length))
            start += length + 1
        }
        lines = result
        totalLength = text.utf16.count
    }

    public func utf16Offset(line: Int, column: Int) -> Int {
        guard line >= 1 else { return 0 }
        guard line <= lines.count else { return totalLength }
        let entry = lines[line - 1]
        let targetBytes = max(column - 1, 0)
        if entry.isASCII { return entry.utf16Start + min(targetBytes, entry.utf16Length) }
        var bytes = 0
        var units = 0
        for scalar in entry.text.unicodeScalars {
            if bytes >= targetBytes { break }
            bytes += String(scalar).utf8.count
            units += scalar.utf16.count
        }
        return entry.utf16Start + units
    }

    public func nsRange(_ range: SourceRange) -> NSRange {
        let lower = utf16Offset(line: range.lowerBound.line, column: range.lowerBound.column)
        let upper = utf16Offset(line: range.upperBound.line, column: range.upperBound.column)
        return NSRange(location: lower, length: max(upper - lower, 0))
    }
}
