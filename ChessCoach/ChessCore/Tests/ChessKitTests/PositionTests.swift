import XCTest
@testable import ChessKit

final class PositionTests: XCTestCase {
    func testStartingPositionFENRoundTrip() {
        let position = Position.standard
        XCTAssertEqual(position.fen, Position.startingFEN)
        XCTAssertEqual(position.sideToMove, .white)
        XCTAssertEqual(position.castlingRights, .all)
        XCTAssertNil(position.enPassantSquare)
        XCTAssertEqual(position.piece(at: Square(algebraic: "e1")!), Piece(.white, .king))
        XCTAssertEqual(position.piece(at: Square(algebraic: "d8")!), Piece(.black, .queen))
    }

    func testSquareGeometry() {
        let a1 = Square(algebraic: "a1")!
        XCTAssertEqual(a1.file, 0)
        XCTAssertEqual(a1.rank, 0)
        XCTAssertEqual(a1.name, "a1")
        XCTAssertFalse(a1.isLight)

        let h8 = Square(algebraic: "h8")!
        XCTAssertEqual(h8.file, 7)
        XCTAssertEqual(h8.rank, 7)
        XCTAssertFalse(h8.isLight)
        XCTAssertEqual(a1.distance(to: h8), 7)

        XCTAssertNil(Square(algebraic: "i9"))
        XCTAssertEqual(Square(compactIndex: 63).name, "h8")
    }

    func testMakeAndUnmakeRestoresPosition() {
        var position = Position.standard
        let before = position
        let moves = position.generateLegalMoves()
        for move in moves {
            let undo = position.make(move)
            position.unmake(undo)
            XCTAssertEqual(position, before, "unmake failed for \(move.uci)")
            XCTAssertEqual(position.fen, before.fen)
        }
    }

    func testCastlingMovesTheRook() {
        var position = Position(fen: "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")!
        let castle = position.legalMove(uci: "e1g1")!
        XCTAssertTrue(castle.isKingsideCastle)
        position.make(castle)
        XCTAssertEqual(position.piece(at: Square(algebraic: "g1")!), Piece(.white, .king))
        XCTAssertEqual(position.piece(at: Square(algebraic: "f1")!), Piece(.white, .rook))
        XCTAssertNil(position.piece(at: Square(algebraic: "h1")!))
        XCTAssertFalse(position.castlingRights.contains(.whiteKingside))
        XCTAssertFalse(position.castlingRights.contains(.whiteQueenside))
    }

    func testCannotCastleThroughCheck() {
        // A black rook on f8 covers f1, so kingside castling is illegal.
        let position = Position(fen: "4kr2/8/8/8/8/8/8/4K2R w K - 0 1")!
        XCTAssertNil(position.legalMove(uci: "e1g1"))
    }

    func testEnPassantCapture() {
        var position = Position(fen: "rnbqkbnr/ppp1p1pp/8/3pPp2/8/8/PPPP1PPP/RNBQKBNR w KQkq f6 0 3")!
        let enPassant = position.legalMove(uci: "e5f6")!
        XCTAssertTrue(enPassant.isEnPassant)
        position.make(enPassant)
        XCTAssertNil(position.piece(at: Square(algebraic: "f5")!))
        XCTAssertEqual(position.piece(at: Square(algebraic: "f6")!), Piece(.white, .pawn))
    }

    func testPromotionGeneratesFourChoices() {
        let position = Position(fen: "8/P6k/8/8/8/8/8/7K w - - 0 1")!
        let promotions = position.legalMoves.filter { $0.from == Square(algebraic: "a7")! }
        XCTAssertEqual(promotions.count, 4)
        XCTAssertEqual(Set(promotions.compactMap { $0.promotion }), [.queen, .rook, .bishop, .knight])
    }

    func testCheckmateAndStalemateDetection() {
        let foolsMate = Position(fen: "rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3")!
        XCTAssertTrue(foolsMate.isCheckmate)
        XCTAssertFalse(foolsMate.isStalemate)

        let stalemate = Position(fen: "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")!
        XCTAssertTrue(stalemate.isStalemate)
        XCTAssertFalse(stalemate.isCheckmate)
    }

    func testZobristKeyIsStableAcrossMakeUnmake() {
        var position = Position.standard
        let key = position.zobristKey
        let move = position.legalMove(uci: "e2e4")!
        let undo = position.make(move)
        XCTAssertNotEqual(position.zobristKey, key)
        position.unmake(undo)
        XCTAssertEqual(position.zobristKey, key)
    }

    func testInsufficientMaterial() {
        XCTAssertTrue(Position(fen: "8/8/4k3/8/8/3K4/8/8 w - - 0 1")!.hasInsufficientMaterial)
        XCTAssertTrue(Position(fen: "8/8/4k3/8/8/3K1B2/8/8 w - - 0 1")!.hasInsufficientMaterial)
        XCTAssertFalse(Position(fen: "8/8/4k3/8/8/3K1R2/8/8 w - - 0 1")!.hasInsufficientMaterial)
        XCTAssertFalse(Position.standard.hasInsufficientMaterial)
    }
}
