import Foundation

/// Splits long text for several requests, only at paragraph starts (never inside a paragraph, so a
/// placeholder or a sentence is never cut) and, when it can, right before a heading.
public enum Chunker {
    public static func split(_ text: String, limit: Int = 6000) -> [String] {
        let ns = text as NSString
        guard ns.length > limit else { return [text] }

        let starts = paragraphStarts(in: ns)
        var parts: [String] = []
        var partStart = 0
        while ns.length - partStart > limit {
            let window = (partStart + limit / 2)...(partStart + limit)
            let inWindow = starts.filter { window.contains($0) }
            let cut: Int?
            if let heading = inWindow.last(where: { isHeading(at: $0, in: ns) }) {
                cut = heading
            } else if let paragraph = inWindow.last {
                cut = paragraph
            } else {
                // Nothing in reach: the paragraph is longer than the limit, so extend to the next boundary.
                cut = starts.first { $0 > partStart + limit }
            }
            guard let cut else { break }
            parts.append(ns.substring(with: NSRange(location: partStart, length: cut - partStart)))
            partStart = cut
        }
        parts.append(ns.substring(from: partStart))
        return parts
    }

    public static func join(_ parts: [String]) -> String {
        parts.joined()
    }

    /// Offsets where a paragraph begins after one or more blank lines.
    private static func paragraphStarts(in text: NSString) -> [Int] {
        var starts: [Int] = []
        var index = 0
        while index < text.length {
            guard text.character(at: index) == 0x0A else { index += 1; continue }
            // A run of two or more newlines is a blank line; the next paragraph starts after the run.
            var end = index
            while end < text.length, text.character(at: end) == 0x0A { end += 1 }
            if end - index >= 2, end < text.length { starts.append(end) }
            index = end
        }
        return starts
    }

    private static func isHeading(at offset: Int, in text: NSString) -> Bool {
        text.character(at: offset) == 0x23  // "#"
    }
}
