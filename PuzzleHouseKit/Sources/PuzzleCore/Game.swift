import Foundation

public struct Game: Hashable, Sendable, Codable {
    public let id: String
    public let displayName: String
    public let emoji: String

    /// sRGB components (0–1). Lets `PuzzleUI` paint accent stripes without
    /// pulling in SwiftUI / UIColor here.
    public let red: Double
    public let green: Double
    public let blue: Double

    /// Where tapping the game name should take the user. Stored as a string
    /// so PuzzleCore stays Foundation-only (no UIKit/SwiftUI URL deps).
    public let launchURLString: String?

    public init(
        id: String,
        displayName: String,
        emoji: String,
        red: Double,
        green: Double,
        blue: Double,
        launchURLString: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.emoji = emoji
        self.red = red
        self.green = green
        self.blue = blue
        self.launchURLString = launchURLString
    }

    public var launchURL: URL? {
        launchURLString.flatMap(URL.init(string:))
    }
}

public extension Game {
    static let wordle = Game(
        id: "wordle", displayName: "Wordle", emoji: "🟩",
        red: 0.42, green: 0.66, blue: 0.39,
        launchURLString: "https://www.nytimes.com/games/wordle/index.html"
    )
    static let connections = Game(
        id: "connections", displayName: "Connections", emoji: "🟪",
        red: 0.69, green: 0.51, blue: 0.78,
        launchURLString: "https://www.nytimes.com/games/connections"
    )
    static let strands = Game(
        id: "strands", displayName: "Strands", emoji: "🔵",
        red: 0.23, green: 0.51, blue: 0.96,
        launchURLString: "https://www.nytimes.com/games/strands"
    )
    static let emojiGame = Game(
        id: "emoji_game", displayName: "Emoji Game", emoji: "😀",
        red: 0.95, green: 0.84, blue: 0.25,
        launchURLString: "applenews://"
    )

    static let known: [Game] = [.wordle, .connections, .strands, .emojiGame]

    static func known(by id: String) -> Game? {
        known.first { $0.id == id }
    }
}
