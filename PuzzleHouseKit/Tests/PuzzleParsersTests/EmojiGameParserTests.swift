import XCTest
import PuzzleCore
@testable import PuzzleParsers

final class EmojiGameParserTests: XCTestCase {

    func testSyntheticFormat() throws {
        let text = """
        EmojiGame #42 4/5
        😀😀😀😀😀
        """
        XCTAssertTrue(EmojiGameParser.canParse(text))
        let parsed = try EmojiGameParser.parse(text)
        XCTAssertEqual(parsed.gameID, "emoji_game")
        XCTAssertEqual(parsed.puzzleNumber, 42)
        XCTAssertEqual(parsed.rawScore, .custom(value: 4, solved: false))
        XCTAssertEqual(parsed.metadata["correct"], "4")
        XCTAssertEqual(parsed.metadata["outOf"], "5")
    }

    func testPerfectScoreIsSolved() throws {
        let text = "EmojiGame #43 5/5"
        let parsed = try EmojiGameParser.parse(text)
        XCTAssertEqual(parsed.rawScore, .custom(value: 5, solved: true))
    }

    func testDoesNotMatchWordle() {
        XCTAssertFalse(EmojiGameParser.canParse("Wordle 1,247 4/6"))
    }

    func testMovesFormatSolvedWithLowerIsBetter() throws {
        let text = "EmojiGame #20260519 moves=6"
        XCTAssertTrue(EmojiGameParser.canParse(text))
        let parsed = try EmojiGameParser.parse(text)
        XCTAssertEqual(parsed.puzzleNumber, 20260519)
        // Negated value so fewer moves yield higher goodness in the z-score.
        XCTAssertEqual(parsed.rawScore, .custom(value: -6, solved: true))
        XCTAssertEqual(parsed.metadata["moves"], "6")
    }

    func testFewerMovesYieldsHigherGoodness() throws {
        let a = try EmojiGameParser.parse("EmojiGame #1 moves=3").rawScore.goodness
        let b = try EmojiGameParser.parse("EmojiGame #1 moves=8").rawScore.goodness
        XCTAssertGreaterThan(a, b)
    }
}
