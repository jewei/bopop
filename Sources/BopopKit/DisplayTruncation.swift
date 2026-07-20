import Foundation

/// Shared row-subtitle truncation: several providers (Snippets, Clipboard)
/// show only the first line of multi-line stored text, capped so a single
/// pasted document can't blow out row layout or make Ranker fold a huge
/// string per keystroke.
public nonisolated enum DisplayTruncation {
    /// Returns the first line of `text` (split on any newline), trimmed of
    /// surrounding whitespace, truncated to at most `limit` grapheme
    /// clusters with a trailing ellipsis appended when truncation occurs.
    /// `String.count`/`prefix` operate on grapheme clusters, so this is
    /// safe for multi-scalar characters (emoji, combining marks, etc).
    public static func firstLine(_ text: String, limit: Int) -> String {
        let firstLine = text.components(separatedBy: .newlines).first ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else {
            return trimmed
        }
        return String(trimmed.prefix(limit)) + "…"
    }
}
