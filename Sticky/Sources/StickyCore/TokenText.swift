import Foundation

public enum TokenText {
    /// Cursor stores the access token as a plain string. Some copies include
    /// surrounding quotes from a JSON encoding; those are not part of the token.
    public static func normalize(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count >= 2, text.first == "\"", text.last == "\"" {
            text = String(text.dropFirst().dropLast())
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }
}
