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

    func testReturnsNilWhenNoPuzzleNumberFound() {
        let recognized = "You got 3/5 today"
        XCTAssertNil(OCRPipeline.synthesizeEmojiGame(from: recognized))
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
}
