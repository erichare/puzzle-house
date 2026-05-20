import Foundation

enum ParserHelpers {
    /// Strip BOM, normalize whitespace, drop empty leading lines.
    static func normalize(_ text: String) -> String {
        var s = text
        if s.hasPrefix("\u{FEFF}") {
            s.removeFirst()
        }
        s = s.replacingOccurrences(of: "\r\n", with: "\n")
        s = s.replacingOccurrences(of: "\r", with: "\n")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Parses "1,247" or "1247" into an Int.
    static func parseNumber(_ s: String) -> Int? {
        Int(s.replacingOccurrences(of: ",", with: ""))
    }

    /// First non-empty line of normalized input.
    static func firstLine(_ text: String) -> String {
        normalize(text).split(separator: "\n").first.map(String.init) ?? ""
    }
}

extension StringProtocol {
    /// Count of how many times each scalar from `chars` appears in this string.
    /// Used to count emoji tiles in a grid row.
    func countingOccurrences(of chars: Set<Character>) -> Int {
        reduce(0) { $0 + (chars.contains($1) ? 1 : 0) }
    }
}
