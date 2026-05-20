import XCTest
import PuzzleCore
@testable import PuzzleParsers

final class WordleParserTests: XCTestCase {

    func testHappyPath() throws {
        let text = """
        Wordle 1,247 4/6

        ⬛🟨⬛⬛⬛
        ⬛⬛🟨🟨⬛
        🟨🟩🟨⬛⬛
        🟩🟩🟩🟩🟩
        """
        XCTAssertTrue(WordleParser.canParse(text))
        let parsed = try WordleParser.parse(text)
        XCTAssertEqual(parsed.gameID, "wordle")
        XCTAssertEqual(parsed.puzzleNumber, 1247)
        XCTAssertEqual(parsed.rawScore, .guesses(used: 4, outOf: 6, solved: true))
        XCTAssertEqual(parsed.metadata["hardMode"], "false")
        XCTAssertEqual(parsed.gridData?.components(separatedBy: "\n").count, 4)
    }

    func testHardMode() throws {
        let text = """
        Wordle 1,247 3/6*

        🟨🟨🟨⬛⬛
        🟩🟩🟩⬛⬛
        🟩🟩🟩🟩🟩
        """
        let parsed = try WordleParser.parse(text)
        XCTAssertEqual(parsed.rawScore, .guesses(used: 3, outOf: 6, solved: true))
        XCTAssertEqual(parsed.metadata["hardMode"], "true")
    }

    func testFailedRun() throws {
        let text = """
        Wordle 1,247 X/6

        ⬛⬛⬛⬛⬛
        ⬛⬛⬛⬛⬛
        ⬛⬛⬛⬛⬛
        ⬛🟨⬛⬛⬛
        ⬛⬛🟨🟨⬛
        ⬛🟩⬛⬛⬛
        """
        let parsed = try WordleParser.parse(text)
        XCTAssertEqual(parsed.rawScore, .guesses(used: 7, outOf: 6, solved: false))
        XCTAssertFalse(parsed.rawScore.solved)
    }

    func testLightModeTiles() throws {
        let text = """
        Wordle 1,247 2/6

        ⬜🟨⬜⬜⬜
        🟩🟩🟩🟩🟩
        """
        let parsed = try WordleParser.parse(text)
        XCTAssertEqual(parsed.rawScore, .guesses(used: 2, outOf: 6, solved: true))
    }

    func testNumberWithoutComma() throws {
        let text = """
        Wordle 999 1/6

        🟩🟩🟩🟩🟩
        """
        let parsed = try WordleParser.parse(text)
        XCTAssertEqual(parsed.puzzleNumber, 999)
    }

    func testRejectsForeignFormats() {
        XCTAssertFalse(WordleParser.canParse("Connections\nPuzzle #234\n🟪🟪🟪🟪"))
        XCTAssertFalse(WordleParser.canParse("Strands #100\n🔵🔵🔵🔵"))
        XCTAssertFalse(WordleParser.canParse("just some text"))
    }

    func testMalformedHeaderThrows() {
        let text = "Wordle abc 4/6\n⬛⬛⬛⬛⬛"
        XCTAssertThrowsError(try WordleParser.parse(text))
    }
}
