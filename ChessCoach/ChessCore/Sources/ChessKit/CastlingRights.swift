import Foundation

public struct CastlingRights: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let whiteKingside = CastlingRights(rawValue: 1 << 0)
    public static let whiteQueenside = CastlingRights(rawValue: 1 << 1)
    public static let blackKingside = CastlingRights(rawValue: 1 << 2)
    public static let blackQueenside = CastlingRights(rawValue: 1 << 3)

    public static let all: CastlingRights = [.whiteKingside, .whiteQueenside, .blackKingside, .blackQueenside]
    public static let none: CastlingRights = []

    public static func kingside(_ color: PieceColor) -> CastlingRights {
        return color == .white ? .whiteKingside : .blackKingside
    }

    public static func queenside(_ color: PieceColor) -> CastlingRights {
        return color == .white ? .whiteQueenside : .blackQueenside
    }

    public static func both(_ color: PieceColor) -> CastlingRights {
        return [kingside(color), queenside(color)]
    }

    public func has(_ right: CastlingRights) -> Bool {
        return contains(right)
    }

    public var fenString: String {
        if isEmpty { return "-" }
        var result = ""
        if contains(.whiteKingside) { result += "K" }
        if contains(.whiteQueenside) { result += "Q" }
        if contains(.blackKingside) { result += "k" }
        if contains(.blackQueenside) { result += "q" }
        return result
    }

    public static func parse(fen: String) -> CastlingRights {
        var rights: CastlingRights = []
        for character in fen {
            switch character {
            case "K": rights.insert(.whiteKingside)
            case "Q": rights.insert(.whiteQueenside)
            case "k": rights.insert(.blackKingside)
            case "q": rights.insert(.blackQueenside)
            default: break
            }
        }
        return rights
    }
}
