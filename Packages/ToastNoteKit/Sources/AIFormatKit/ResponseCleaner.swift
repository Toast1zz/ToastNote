import Foundation

/// Models sometimes wrap the whole answer in a ```markdown fence despite the prompt; take it off.
public enum ResponseCleaner {
    public static func clean(_ response: String) -> String {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines = trimmed.components(separatedBy: "\n")
        guard lines.count >= 2,
              let opening = lines.first?.trimmingCharacters(in: .whitespaces),
              ["```", "```markdown", "```md"].contains(opening.lowercased()),
              lines.last?.trimmingCharacters(in: .whitespaces) == "```" else { return trimmed }
        lines.removeFirst()
        lines.removeLast()
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
