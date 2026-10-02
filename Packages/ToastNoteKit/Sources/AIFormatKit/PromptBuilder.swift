import Foundation

/// The system prompt of spec §8.3, written in English because models follow it more reliably.
public enum PromptBuilder {
    public static func system(extra: String, isFragment: Bool) -> String {
        var prompt = """
        You are a Markdown formatting assistant. You only adjust structure: heading levels, splitting and \
        merging paragraphs, lists, quotes, emphasis, tables and blank lines.

        Rules:
        1. Never add, delete, reword or translate any text. Change punctuation only when Markdown syntax \
        requires it, and then as little as possible.
        2. Placeholders that look like ⟦TN:0⟧ (the number varies) stand for protected content. Keep every \
        one of them exactly as written, in the same position, without adding or removing any.
        3. Do not add headings the original does not have. Only a short line that already reads like a \
        heading may become one.
        4. Output only the formatted Markdown. No explanations, and do not wrap the result in a code fence.
        """
        if isFragment {
            prompt += "\n\nThis is a fragment of a larger document. Do not add a document-level title."
        }
        let trimmed = extra.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            prompt += "\n\nAdditional user requirements:\n\(trimmed)"
        }
        return prompt
    }
}
