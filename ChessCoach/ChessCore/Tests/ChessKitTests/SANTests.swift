import XCTest
@testable import ChessKit

final class SANTests: XCTestCase {
    func testBasicSANGeneration() {
        var position = Position.standard
        XCTAssertEqual(position.san(for: position.legalMove(uci: "e2e4")!), "e4")
        XCTAssertEqual(position.san(for: position.legalMove(uci: "g1f3")!), "Nf3")
        position.make(position.legalMove(uci: "e2e4")!)
        XCTAssertEqual(position.san(for: position.legalMove(uci: "e7e5")!), "e5")
    }

    func testCaptureAndCheckNotation() {
        let position = Position(fen: "rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 2")!
        XCTAssertEqual(position.san(for: position.legalMove(uci: "e4d5")!), "exd5")

        let checkPosition = Position(fen: "rnbqkbnr/pppp1ppp/8/4p3/6P1/5P2/PPPPP2P/RNBQKBNR b KQkq g3 0 2")!
        XCTAssertEqual(checkPosition.san(for: checkPosition.legalMove(uci: "d8h4")!), "Qh4#")
    }

    func testDisambiguation() {
        // Knights on b1 and f3 both reach d2, so SAN needs the file letter.
        let position = Position(fen: "4k3/8/8/8/8/5N2/8/1N2K3 w - - 0 1")!
        XCTAssertEqual(position.san(for: position.legalMove(uci: "b1d2")!), "Nbd2")
        XCTAssertEqual(position.san(for: position.legalMove(uci: "f3d2")!), "Nfd2")
        // Only one knight reaches a3, so no disambiguation is added.
        XCTAssertEqual(position.san(for: position.legalMove(uci: "b1a3")!), "Na3")
    }

    func testCastlingAndPromotionNotation() {
        let castling = Position(fen: "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")!
        XCTAssertEqual(castling.san(for: castling.legalMove(uci: "e1g1")!), "O-O")
        XCTAssertEqual(castling.san(for: castling.legalMove(uci: "e1c1")!), "O-O-O")

        let promotion = Position(fen: "8/P6k/8/8/8/8/8/7K w - - 0 1")!
        XCTAssertEqual(promotion.san(for: promotion.legalMove(uci: "a7a8q")!), "a8=Q")
        XCTAssertEqual(promotion.san(for: promotion.legalMove(uci: "a7a8n")!), "a8=N")
    }

    func testSANParsingRoundTrip() {
        var position = Position.standard
        for text in ["e4", "e5", "Nf3", "Nc6", "Bb5", "a6", "Ba4", "Nf6", "O-O", "Be7"] {
            guard let move = position.move(san: text) else {
                XCTFail("Could not parse \(text)")
                return
            }
            XCTAssertEqual(position.san(for: move), text)
            position.make(move)
        }
        XCTAssertEqual(position.fullmoveNumber, 6)
    }

    func testGameTracksResultAndPGN() {
        var game = Game()
        for text in ["f3", "e5", "g4", "Qh4"] {
            XCTAssertNotNil(game.play(san: text), "failed to play \(text)")
        }
        XCTAssertEqual(game.result, .win(.black, .checkmate))
        XCTAssertTrue(game.pgn().contains("1. f3 e5 2. g4 Qh4#"))
    }
}
