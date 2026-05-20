import XCTest
import PuzzleCore
@testable import PuzzleParsers

final class StrandsParserTests: XCTestCase {

    func testNoHintsWithTheme() throws {
        let text = """
        Strands #234
        "Tropical fruits"
        🔵🔵🟡🔵
        🔵🔵🔵🔵
        """
        XCTAssertTrue(StrandsParser.canParse(text))
        let parsed = try StrandsParser.parse(text)
        XCTAssertEqual(parsed.gameID, "strands")
        XCTAssertEqual(parsed.puzzleNumber, 234)
        XCTAssertEqual(parsed.rawScore, .hints(count: 0, solved: true))
        XCTAssertEqual(parsed.metadata["theme"], "Tropical fruits")
    }

    func testWithHints() throws {
        let text = """
        Strands #235
        💡🔵🟡🔵
        🔵💡🔵🔵
        """
        let parsed = try StrandsParser.parse(text)
        XCTAssertEqual(parsed.rawScore, .hints(count: 2, solved: true))
    }

    func testHashOptionalInHeader() throws {
        let text = """
        Strands 100
        🔵🟡🔵🔵
        """
        let parsed = try StrandsParser.parse(text)
        XCTAssertEqual(parsed.puzzleNumber, 100)
    }

    func testRejectsForeign() {
        XCTAssertFalse(StrandsParser.canParse("Wordle 1,247 4/6"))
        XCTAssertFalse(StrandsParser.canParse("Connections\nPuzzle #1"))
    }
}
