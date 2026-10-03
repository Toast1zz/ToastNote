import Foundation

/// One replacement plus where the selection ends up; applied by the text view as a single undo step.
public struct TextEdit: Equatable, Sendable {
    public var range: NSRange
    public var replacement: String
    public var selectionAfter: NSRange

    public init(range: NSRange, replacement: String, selectionAfter: NSRange) {
        self.range = range
        self.replacement = replacement
        self.selectionAfter = selectionAfter
    }
}

/// Pure editing helpers behind the formatting shortcuts and list handling (spec §7.5).
public enum EditingCommands {
    // MARK: Wrapping

    /// Wraps the selection in `marker`, or unwraps it when it is already wrapped.
    /// With an empty selection it inserts a pair and puts the caret between the markers.
    public static func toggleWrap(_ marker: String, text: NSString, selection: NSRange) -> TextEdit {
        let markerLength = (marker as NSString).length
        let selected = text.substring(with: selection) as NSString

        // Markers inside the selection: "**abc**" selected as a whole.
        if selection.length >= markerLength * 2, selected.hasPrefix(marker), selected.hasSuffix(marker) {
            let inner = selected.substring(with: NSRange(location: markerLength, length: selected.length - markerLength * 2))
            return TextEdit(range: selection, replacement: inner, selectionAfter: NSRange(location: selection.location, length: (inner as NSString).length))
        }

        // Markers just outside the selection: "abc" selected inside "**abc**" (or caret inside "**|**").
        let before = NSRange(location: selection.location - markerLength, length: markerLength)
        let after = NSRange(location: NSMaxRange(selection), length: markerLength)
        if before.location >= 0, NSMaxRange(after) <= text.length,
           text.substring(with: before) == marker, text.substring(with: after) == marker,
           !isPartOfLongerRun(marker, text: text, before: before, after: after) {
            let whole = NSRange(location: before.location, length: NSMaxRange(after) - before.location)
            return TextEdit(
                range: whole, replacement: selected as String,
                selectionAfter: NSRange(location: before.location, length: selection.length)
            )
        }

        return TextEdit(
            range: selection, replacement: marker + (selected as String) + marker,
            selectionAfter: NSRange(location: selection.location + markerLength, length: selection.length)
        )
    }

    /// `*` inside `**bold**` must not be mistaken for an italic wrapper of its own.
    private static func isPartOfLongerRun(_ marker: String, text: NSString, before: NSRange, after: NSRange) -> Bool {
        guard marker.count == 1, let char = marker.utf16.first else { return false }
        let left = before.location - 1
        let right = NSMaxRange(after)
        let leftSame = left >= 0 && text.character(at: left) == char
        let rightSame = right < text.length && text.character(at: right) == char
        return leftSame || rightSame
    }

    public static func insertLink(text: NSString, selection: NSRange) -> TextEdit {
        let selected = text.substring(with: selection)
        let replacement = "[\(selected)]()"
        // With a selection the caret lands inside "()" for the URL; without one, inside "[]".
        let caret = selection.length == 0 ? selection.location + 1 : selection.location + (selected as NSString).length + 3
        return TextEdit(range: selection, replacement: replacement, selectionAfter: NSRange(location: caret, length: 0))
    }

    // MARK: Lists

    private struct ListLine {
        var indent: String
        var marker: String      // "-", "*", "+", "1." or "1)"
        var task: Bool
        var contentStart: Int   // UTF-16 offset in the line where the item text begins
        var isEmpty: Bool
    }

    private static let listPattern = try! NSRegularExpression(pattern: #"^([ \t]*)([-*+]|\d+[.)])[ \t]+(\[[ xX]\][ \t]+)?"#)

    private static func listLine(_ line: String) -> ListLine? {
        let ns = line as NSString
        guard let match = listPattern.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let end = NSMaxRange(match.range)
        return ListLine(
            indent: ns.substring(with: match.range(at: 1)),
            marker: ns.substring(with: match.range(at: 2)),
            task: match.range(at: 3).location != NSNotFound,
            contentStart: end,
            isEmpty: ns.substring(from: end).trimmingCharacters(in: .whitespaces).isEmpty
        )
    }

    private static func nextMarker(_ marker: String) -> String {
        guard let last = marker.last, last == "." || last == ")", let number = Int(marker.dropLast()) else { return marker }
        return "\(number + 1)\(last)"
    }

    /// List continuation for Return; nil means "not a list item, use the default behavior".
    public static func newline(text: NSString, caret: Int) -> TextEdit? {
        let lineRange = text.lineRange(for: NSRange(location: caret, length: 0))
        var contentsEnd = 0, start = 0, end = 0
        text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: lineRange)
        let line = text.substring(with: NSRange(location: start, length: contentsEnd - start))
        guard let item = listLine(line), caret >= start + item.contentStart else { return nil }

        if item.isEmpty, caret == contentsEnd {
            // Return on an empty item leaves the list. A blank line goes in front of the caret: a line right after
            // an item would continue that item (a Markdown "lazy continuation"), not start a paragraph.
            let range = NSRange(location: start, length: contentsEnd - start)
            let afterBlankLine = start == 1 || (start >= 2 && text.character(at: start - 2) == 0x0A)
            let separator = start > 0 && !afterBlankLine ? "\n" : ""
            return TextEdit(range: range, replacement: separator, selectionAfter: NSRange(location: start + (separator as NSString).length, length: 0))
        }
        let insertion = "\n" + item.indent + nextMarker(item.marker) + " " + (item.task ? "[ ] " : "")
        return TextEdit(
            range: NSRange(location: caret, length: 0), replacement: insertion,
            selectionAfter: NSRange(location: caret + (insertion as NSString).length, length: 0)
        )
    }

    /// Indents or outdents every selected line; nil unless all of them are list items (and, when
    /// outdenting, at least one can move).
    public static func indent(text: NSString, selection: NSRange, outdent: Bool) -> TextEdit? {
        var start = 0, end = 0, contentsEnd = 0
        text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: selection)
        let block = NSRange(location: start, length: contentsEnd - start)
        let lines = text.substring(with: block).components(separatedBy: "\n")
        guard lines.allSatisfy({ listLine($0) != nil }) else { return nil }

        var deltas: [Int] = []
        var rebuilt: [String] = []
        for line in lines {
            if outdent {
                let removable = line.hasPrefix("\t") ? 1 : min(2, line.prefix(while: { $0 == " " }).count)
                deltas.append(-removable)
                rebuilt.append(String(line.dropFirst(removable)))
            } else {
                deltas.append(2)
                rebuilt.append("  " + line)
            }
        }
        guard deltas.contains(where: { $0 != 0 }) else { return nil }

        // Lines starting at or before the selection start move it; later lines inside it grow or shrink it.
        var location = selection.location
        var length = selection.length
        var lineStart = block.location
        for (index, line) in lines.enumerated() {
            if lineStart <= selection.location {
                location += deltas[index]
            } else if lineStart <= NSMaxRange(selection) {
                length += deltas[index]
            }
            lineStart += (line as NSString).length + 1
        }
        return TextEdit(
            range: block, replacement: rebuilt.joined(separator: "\n"),
            selectionAfter: NSRange(location: max(location, block.location), length: max(length, 0))
        )
    }
}
