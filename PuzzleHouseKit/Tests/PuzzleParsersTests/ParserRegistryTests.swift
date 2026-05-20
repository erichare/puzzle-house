import XCTest
import PuzzleCore
@testable import PuzzleParsers

final class ParserRegistryTests: XCTestCase {

    func testDispatchesToCorrectParser() {
        let wordle = "Wordle 1,247 2/6\n\n⬛🟨⬛⬛⬛\n🟩🟩🟩🟩🟩"
        let connections = "Connections\nPuzzle #1\n🟨🟨🟨🟨"
        let strands = "Strands #2\n🔵🔵🔵🔵"
        let emoji = "EmojiGame #3 4/5"

        XCTAssertEqual(ParserRegistry.parse(wordle)?.gameID, "wordle")
        XCTAssertEqual(ParserRegistry.parse(connections)?.gameID, "connections")
        XCTAssertEqual(ParserRegistry.parse(strands)?.gameID, "strands")
        XCTAssertEqual(ParserRegistry.parse(emoji)?.gameID, "emoji_game")
    }

    func testReturnsNilForUnknown() {
        XCTAssertNil(ParserRegistry.parse("hello world"))
        XCTAssertNil(ParserRegistry.parse(""))
    }

    func testDisplayNameLookup() {
        XCTAssertEqual(ParserRegistry.displayName(for: "wordle"), "Wordle")
        XCTAssertEqual(ParserRegistry.displayName(for: "connections"), "Connections")
        XCTAssertNil(ParserRegistry.displayName(for: "unknown"))
    }
}
