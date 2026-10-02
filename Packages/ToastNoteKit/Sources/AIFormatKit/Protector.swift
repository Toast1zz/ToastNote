import EditorKit
import Foundation

public struct Protected: Sendable, Equatable {
    public var text: String
    /// The original content behind each `⟦TN:n⟧` placeholder, indexed by n.
    public var slots: [String]
}

/// Swaps content the model must never touch (frontmatter, code, link targets, images, bare URLs) for
/// `⟦TN:n⟧` placeholders before sending, and puts it back afterwards (spec §8.4).
public enum Protector {
    private static let placeholder = try! NSRegularExpression(pattern: "⟦TN:(\\d+)⟧")

    public static func protect(_ markdown: String) -> Protected {
        let ns = markdown as NSString
        var ranges: [NSRange] = []
        for block in BlockParser.parse(markdown) {
            switch block.kind {
            case .frontmatter, .codeBlock:
                ranges.append(block.range)
            default:
                for span in block.inlines {
                    switch span.kind {
                    case .inlineCode, .image, .bareURL:
                        ranges.append(span.range)
                    case .link:
                        // "](url)" is the second syntax range; protect only the url between the parentheses.
                        if span.syntaxRanges.count == 2 {
                            let tail = span.syntaxRanges[1]
                            if tail.length > 3 {
                                ranges.append(NSRange(location: tail.location + 2, length: tail.length - 3))
                            }
                        }
                    default:
                        break
                    }
                }
            }
        }

        // Keep the outermost ranges only, in document order.
        ranges.sort { $0.location != $1.location ? $0.location < $1.location : $0.length > $1.length }
        var kept: [NSRange] = []
        for range in ranges where range.length > 0 {
            if let last = kept.last, NSMaxRange(range) <= NSMaxRange(last) { continue }
            if let last = kept.last, range.location < NSMaxRange(last) { continue }
            kept.append(range)
        }

        let slots = kept.map { ns.substring(with: $0) }
        let result = NSMutableString(string: markdown)
        for (index, range) in kept.enumerated().reversed() {
            result.replaceCharacters(in: range, with: "⟦TN:\(index)⟧")
        }
        return Protected(text: result as String, slots: slots)
    }

    /// Puts the protected content back. A placeholder that is missing, duplicated or unknown means the
    /// model damaged the text, so the whole result is rejected.
    public static func restore(_ text: String, slots: [String]) throws -> String {
        let ns = text as NSString
        let matches = placeholder.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var seen = Set<Int>()
        for match in matches {
            guard let index = Int(ns.substring(with: match.range(at: 1))),
                  slots.indices.contains(index), seen.insert(index).inserted else { throw AIError.incompleteResult }
        }
        guard seen.count == slots.count else { throw AIError.incompleteResult }

        let result = NSMutableString(string: text)
        for match in matches.reversed() {
            let index = Int(ns.substring(with: match.range(at: 1)))!
            result.replaceCharacters(in: match.range, with: slots[index])
        }
        return result as String
    }
}
