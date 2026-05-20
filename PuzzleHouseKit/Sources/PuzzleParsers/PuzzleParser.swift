import Foundation
import PuzzleCore

public protocol PuzzleParser {
    static var gameID: String { get }
    static var displayName: String { get }
    static func canParse(_ text: String) -> Bool
    static func parse(_ text: String) throws -> ParsedResult
}

public enum PuzzleParserError: Error, Equatable, Sendable {
    case unrecognizedFormat
    case missingHeader(gameID: String)
    case malformedScore(gameID: String, detail: String)
    case malformedGrid(gameID: String, detail: String)
}
