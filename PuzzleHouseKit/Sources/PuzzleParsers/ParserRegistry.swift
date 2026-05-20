import Foundation
import PuzzleCore

public enum ParserRegistry {
    public static let all: [any PuzzleParser.Type] = [
        WordleParser.self,
        ConnectionsParser.self,
        StrandsParser.self,
        EmojiGameParser.self,
    ]

    public static func parser(for text: String) -> (any PuzzleParser.Type)? {
        all.first { $0.canParse(text) }
    }

    public static func parse(_ text: String) -> ParsedResult? {
        guard let p = parser(for: text) else { return nil }
        return try? p.parse(text)
    }

    public static func displayName(for gameID: String) -> String? {
        all.first { $0.gameID == gameID }?.displayName
    }
}
