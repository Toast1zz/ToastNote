import Foundation

/// The single tag rule shared by the editor and the index (spec §10.3).
public enum TagParser {
    /// Finds inline `#tags`. Ranges are UTF-16 and include the leading `#`.
    public static func tags(in text: String, excluding: [NSRange] = []) -> [(tag: String, range: NSRange)] {
        var result: [(tag: String, range: NSRange)] = []
        var utf16Offset = 0
        var previous: Unicode.Scalar?
        let scalars = Array(text.unicodeScalars)
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            let atBoundary = previous == nil || previous!.properties.isWhitespace
            if scalar == "#", atBoundary {
                var end = index + 1
                var length = 0
                while end < scalars.count, isTagScalar(scalars[end]) {
                    length += scalars[end].utf16.count
                    end += 1
                }
                if end > index + 1 {
                    let name = String(String.UnicodeScalarView(scalars[(index + 1)..<end]))
                    let range = NSRange(location: utf16Offset, length: length + 1)
                    let isNumeric = name.unicodeScalars.allSatisfy { $0.properties.numericType != nil }
                    if !isNumeric, !excluding.contains(where: { NSIntersectionRange($0, range).length > 0 }) {
                        result.append((name, range))
                    }
                }
                // Skip the scanned run so its characters are not re-examined as a tag start.
                for consumed in index..<end { utf16Offset += scalars[consumed].utf16.count }
                previous = end > index ? scalars[end - 1] : scalar
                index = end
                continue
            }
            utf16Offset += scalar.utf16.count
            previous = scalar
            index += 1
        }
        return result
    }

    private static func isTagScalar(_ scalar: Unicode.Scalar) -> Bool {
        if scalar == "_" || scalar == "-" || scalar == "/" { return true }
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .decimalNumber, .letterNumber, .otherNumber:
            return true
        default:
            return false
        }
    }
}
