import XCTest
import PuzzleCore
import PuzzleParsers
import PuzzleVision

/// Exercises the OCR text → synthetic Emoji Game parser-input bridge. The
/// Vision step itself is hard to test without bundled reference images, so we
/// drive it from text that mimics what Vision would emit.
final class EmojiGameOCRTests: XCTestCase {

    func testSynthesizesFromCleanOCRText() {
        let recognized = """
        Emoji Game #42
        You got 4/5 today
        Try again tomorrow!
        """
        let synth = OCRPipeline.synthesizeEmojiGame(from: recognized)
        XCTAssertEqual(synth, "EmojiGame #42 4/5")
        let parsed = ParserRegistry.parse(synth!)
        XCTAssertEqual(parsed?.gameID, "emoji_game")
        XCTAssertEqual(parsed?.puzzleNumber, 42)
    }

    func testReturnsNilWhenNoScoreFound() {
        let recognized = "Emoji Game #42\nNo score visible"
        XCTAssertNil(OCRPipeline.synthesizeEmojiGame(from: recognized))
    }

    func testFallsBackToDateWhenNoPuzzleNumberFound() {
        let recognized = "You got 3/5 today"
        var c = DateComponents()
        c.year = 2026; c.month = 5; c.day = 19
        c.timeZone = TimeZone(identifier: "UTC")
        let date = Calendar(identifier: .gregorian).date(from: c)!
        let synth = OCRPipeline.synthesizeEmojiGame(
            from: recognized, today: date, timeZone: TimeZone(identifier: "UTC")!
        )
        XCTAssertEqual(synth, "EmojiGame #20260519 3/5")
    }

    func testHandlesNoisyLinesAroundTheScore() {
        let recognized = """
        9:41 AM
        Apple News  #128
        🙂 🤔 🎯 🤩 ❓
        3/5  correct
        Share Score
        """
        let synth = OCRPipeline.synthesizeEmojiGame(from: recognized)
        XCTAssertEqual(synth, "EmojiGame #128 3/5")
    }

    func testMovesPatternFromAppleNewsSolveScreen() {
        let recognized = """
        Leaderboards
        Get started:
        🤩
        6 moves
        BLUE CHEESE
        Dairy product with colorful "veins" or spots
        PUFFER JACKET
        Cold weather top filled with fluffy down
        PRINCE AND THE REVOLUTION
        "Purple Rain" performers
        More Puzzles
        """
        var c = DateComponents()
        c.year = 2026; c.month = 5; c.day = 19
        c.timeZone = TimeZone(identifier: "UTC")
        let date = Calendar(identifier: .gregorian).date(from: c)!
        let synth = OCRPipeline.synthesizeEmojiGame(
            from: recognized, today: date, timeZone: TimeZone(identifier: "UTC")!
        )!
        XCTAssertTrue(synth.hasPrefix("EmojiGame #20260519 moves=6"))
        XCTAssertTrue(synth.contains("BLUE CHEESE"))
        XCTAssertTrue(synth.contains("PUFFER JACKET"))
        XCTAssertTrue(synth.contains("PRINCE AND THE REVOLUTION"))
        XCTAssertFalse(synth.contains("MORE PUZZLES"))
    }

    func testCategoryExtractorDropsChromeAndKeepsAnswers() {
        let lines = [
            "Leaderboards",
            "SHARE",
            "BLUE CHEESE",
            "Cold weather top",
            "PUFFER JACKET",
            "GET STARTED:",
            "More Puzzles",
            "PRINCE AND THE REVOLUTION",
            "EXTRA CATEGORY 4",      // should be capped at 3
        ]
        let cats = OCRPipeline.extractEmojiGameCategories(from: lines)
        XCTAssertEqual(cats, ["BLUE CHEESE", "PUFFER JACKET", "PRINCE AND THE REVOLUTION"])
    }
}
