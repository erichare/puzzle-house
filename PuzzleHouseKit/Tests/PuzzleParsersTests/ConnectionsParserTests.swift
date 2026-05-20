import XCTest
import PuzzleCore
@testable import PuzzleParsers

final class ConnectionsParserTests: XCTestCase {

    func testCleanSolve() throws {
        let text = """
        Connections
        Puzzle #234
        🟨🟨🟨🟨
        🟩🟩🟩🟩
        🟪🟪🟪🟪
        🟦🟦🟦🟦
        """
        XCTAssertTrue(ConnectionsParser.canParse(text))
        let parsed = try ConnectionsParser.parse(text)
        XCTAssertEqual(parsed.gameID, "connections")
        XCTAssertEqual(parsed.puzzleNumber, 234)
        XCTAssertEqual(parsed.rawScore, .mistakes(count: 0, maxAllowed: 4, solved: true))
    }

    func testWithOneMistake() throws {
        let text = """
        Connections
        Puzzle #235
        🟨🟩🟨🟨
        🟨🟨🟨🟨
        🟩🟩🟩🟩
        🟪🟪🟪🟪
        🟦🟦🟦🟦
        """
        let parsed = try ConnectionsParser.parse(text)
        XCTAssertEqual(parsed.rawScore, .mistakes(count: 1, maxAllowed: 4, solved: true))
        XCTAssertEqual(parsed.metadata["correctGroups"], "4")
    }

    func testFailedRun() throws {
        let text = """
        Connections
        Puzzle #236
        🟨🟩🟨🟨
        🟨🟩🟦🟨
        🟦🟪🟪🟪
        🟦🟪🟦🟪
        """
        let parsed = try ConnectionsParser.parse(text)
        // 4 mistakes, no correct groups
        XCTAssertEqual(parsed.rawScore, .mistakes(count: 4, maxAllowed: 4, solved: false))
    }

    func testPuzzleHashOptional() throws {
        let text = """
        Connections
        Puzzle 237
        🟨🟨🟨🟨
        🟩🟩🟩🟩
        🟦🟦🟦🟦
        🟪🟪🟪🟪
        """
        let parsed = try ConnectionsParser.parse(text)
        XCTAssertEqual(parsed.puzzleNumber, 237)
    }

    func testRejectsWordle() {
        XCTAssertFalse(ConnectionsParser.canParse("Wordle 1,247 4/6"))
    }
}
