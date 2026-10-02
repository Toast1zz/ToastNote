import Foundation

/// Line-based frontmatter handling; deliberately no YAML library (spec §10.3).
public enum FrontmatterParser {
    /// Splits a leading `---` ... `---` block from the body. The range excludes the closing line's newline.
    public static func split(_ text: String) -> (frontmatter: NSRange?, body: Substring) {
        let whole = text[...]
        guard text.hasPrefix("---") else { return (nil, whole) }
        var lineStart = text.startIndex
        var offset = 0
        var isFirst = true
        while lineStart < text.endIndex {
            let lineEnd = text[lineStart...].firstIndex(of: "\n") ?? text.endIndex
            let line = text[lineStart..<lineEnd]
            let lineLength = line.utf16.count
            if isFirst {
                guard line.trimmingCharacters(in: .whitespaces) == "---" else { return (nil, whole) }
                isFirst = false
            } else if line.trimmingCharacters(in: .whitespaces) == "---" || line.trimmingCharacters(in: .whitespaces) == "..." {
                let range = NSRange(location: 0, length: offset + lineLength)
                let bodyStart = lineEnd < text.endIndex ? text.index(after: lineEnd) : lineEnd
                return (range, text[bodyStart...])
            }
            offset += lineLength + 1
            lineStart = lineEnd < text.endIndex ? text.index(after: lineEnd) : text.endIndex
        }
        return (nil, whole)
    }

    /// Reads `tags: [a, b]` or a YAML block list. `tags: a, b` is not supported.
    public static func tags(in text: String) -> [String] {
        let (range, _) = split(text)
        guard let range else { return [] }
        let block = (text as NSString).substring(with: range)
        let lines = block.components(separatedBy: "\n").dropFirst().dropLast()
        var result: [String] = []
        var inTagsList = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if inTagsList {
                if trimmed.hasPrefix("- ") || trimmed == "-" {
                    result.append(contentsOf: clean(String(trimmed.dropFirst())))
                    continue
                }
                if trimmed.isEmpty { continue }
                inTagsList = false
            }
            guard line.hasPrefix("tags:") else { continue }
            let value = line.dropFirst("tags:".count).trimmingCharacters(in: .whitespaces)
            if value.isEmpty {
                inTagsList = true
            } else if value.hasPrefix("["), value.hasSuffix("]") {
                let inner = value.dropFirst().dropLast()
                for item in inner.split(separator: ",") { result.append(contentsOf: clean(String(item))) }
            }
        }
        return result
    }

    private static func clean(_ raw: String) -> [String] {
        var value = raw.trimmingCharacters(in: .whitespaces)
        if value.count >= 2, let first = value.first, let last = value.last,
           (first == "\"" && last == "\"") || (first == "'" && last == "'") {
            value = String(value.dropFirst().dropLast())
        }
        if value.hasPrefix("#") { value.removeFirst() }
        return value.isEmpty ? [] : [value]
    }
}
