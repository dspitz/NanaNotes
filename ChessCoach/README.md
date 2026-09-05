# Chess Coach

A chess app whose main mode is *learning*, not playing. The engine is there to be
explained, not just to beat you: every move it likes comes with a reason, every
position comes with a plan for both sides, and at any point you can freeze the
game, play the position out to see what would happen, and step back into the
real game exactly where you left it.

This is a first working slice, not a finished product. What is here is real —
correct rules, a searching engine, an analysis layer and a SwiftUI app — and the
[Roadmap](#roadmap) says what is deliberately not here yet.

---

## Platform: one SwiftUI app for iPhone, iPad and Mac

Phone first, Mac for free. The target is multiplatform (`SDKROOT = auto`), so the
same code builds and runs on iOS 17+ and macOS 14+ — no Catalyst, no second
codebase. The layout switches at 880pt: board over coach panel on a phone,
board beside coach panel on iPad and Mac.

The reason to go phone-first is that the coach is a *conversation* — you make a
move, it reacts, you ask for a hint, you go and try something in the sandbox.
That is a thing people do on a sofa. The Mac build is where the wide layout and
the deeper analysis are pleasant, and it costs nothing extra to keep.

## What it does today

**Play a real game** against a built-in opponent at five strengths, from one that
hangs pieces to one that plays the best move it can find.

**Live coaching that is about the game, not just the move.** The panel beside the
board shows:

- **Winning chances**, as a percentage, with the engine evaluation next to it.
  Probabilities are the headline number because "+1.35" means nothing to most
  people and "72% to win" means something to everyone.
- **Where the game stands** — which terms of the evaluation are actually
  responsible for the score. "King safety favours you, pawn structure favours
  them" rather than a bare number.
- **What they are up to** — the opponent's threats, found by asking the engine
  what it would play if you passed. That difference *is* the list of things you
  have to answer.
- **Plans** for both sides, phase-aware: develop and castle in the opening,
  target the weak pawns and improve your worst piece in the middlegame, activate
  the king and push the passer in the endgame. Tapping a plan highlights the
  squares it is about.
- **Moves worth considering** — the top four candidates with a one-line reason
  each, drawn from what the move does on the board (forks, pins, discovered
  attacks, exchanges, mobility) rather than from the score alone.
- **What matters here** — the durable strategic themes: open files, outposts,
  the bishop pair, passed pawns, weak pawns, space, king safety.

**A hint ladder instead of an answer.** Ask for help and you get a nudge first
("you are being threatened; find the move that deals with it"), then the area of
the board, then which piece, then the move, then the whole line. You keep the
chance to find it yourself.

**Move-by-move feedback.** Every move you play is graded — brilliant / best /
excellent / good / inaccuracy / mistake / blunder — on how much *winning chance*
it cost, not raw centipawns, so a sloppy move in a won position is not
melodramatically labelled a blunder. When it is a mistake, the coach says what
the opponent can now play and what you should have played instead.

**The sandbox.** Tap *Try it out* and the game freezes. The board grows a purple
frame, and now nothing you do counts: play the position out, branch, rewind,
compare lines. The engine can answer as your opponent, as the toughest possible
defence, or not at all while you push both sides' pieces around. Each move you
try gets graded and explained as you make it. *Back to the game* restores the
real position — the game was never touched.

**Game review.** At the end, an accuracy score for both sides and the handful of
moments that actually decided the game, worst first.

## How it is put together

```
ChessCoach/
├── ChessCore/                     Swift package — no UI, fully testable
│   ├── Sources/ChessKit/          The rules of chess and nothing else
│   │   ├── Piece / Square / Move / CastlingRights
│   │   ├── Position               0x88 board, make/unmake, attack detection
│   │   ├── MoveGeneration         legal moves, castling, en passant, perft
│   │   ├── SAN                    notation in and out
│   │   ├── Zobrist                deterministic hashing
│   │   └── Game                   history, repetition, results, PGN
│   ├── Sources/CoachKit/          Everything that has an opinion
│   │   ├── Evaluator              explainable evaluation, term by term
│   │   ├── PieceSquareTables
│   │   ├── ChessEngine            alpha-beta + TT + killers + quiescence
│   │   ├── Evaluation             scores, mates, win/draw/loss probability
│   │   ├── Tactics                SEE, hanging pieces, forks, pins, skewers
│   │   ├── PositionFeatures       the facts a coach would name
│   │   ├── PositionAnalysis       threats, candidates, themes, plans
│   │   ├── CoachNarrator          facts to prose, with the hint ladder
│   │   ├── MoveReview             grading played moves, and game accuracy
│   │   ├── ExplorationTree        the sandbox's branching variations
│   │   └── CoachService           async front door, one serial engine queue
│   └── Tests/                     perft, SAN, tactics, engine, analysis
├── ChessCoach/                    SwiftUI app
└── ChessCoach.xcodeproj
```

Three rules shaped the design:

1. **The rules layer knows nothing about coaching.** `ChessKit` has no
   evaluation and no opinions, which is why it can be proved correct with perft.
2. **The score and the explanation come from the same place.** `Evaluator`
   returns a *breakdown*, not a number, and `PositionFeatures` collects the same
   facts the narrator uses. The coach can never say "your king is safe" while the
   evaluation is punishing you for king safety.
3. **The UI never blocks and never lies.** Every engine call goes through
   `CoachService` onto one serial queue; results are dropped if the position has
   moved on; the evaluation bar dims while it is stale rather than showing a
   stale number as though it were fresh.

### About "AI"

The coaching is a real engine plus a deterministic explanation layer, running
entirely on device. Nothing is sent anywhere, it works on a plane, and it is
reproducible: the same position always produces the same advice.

`CoachCommentary` is a plain value — headline, assessment, paragraphs, threats,
plans, hints — so a language model can be layered on later purely to *rephrase*
what the analysis already established, or to answer free-form questions with the
report as context. The analysis itself should stay where it is; an LLM asked to
evaluate a chess position directly is worse than a 200-line evaluator.

## Building

Requires **Xcode 16 or later** (the project uses file-system synchronised
groups), targeting iOS 17+ / macOS 14+.

```sh
open ChessCoach/ChessCoach.xcodeproj
```

Pick the `ChessCoach` scheme and run on an iOS simulator, a device, or My Mac.

To run the engine tests without opening Xcode:

```sh
cd ChessCoach/ChessCore
swift test
```

> These sources were written in a Linux container with no Swift toolchain
> available, so the package has not been compiled or the tests run yet. Expect to
> fix a few compile errors on the first build. The tests are the place to start:
> `PerftTests` proves the move generator, and everything else rests on it.

## Roadmap

Deliberately not in this slice:

- **Opening book and named openings** — "this is a Sicilian Najdorf, and the idea
  behind ...a6 is..." is one of the most valuable things a coach can say, and it
  needs a book, not a search.
- **Endgame tablebases** for exact play in simple endings.
- **Puzzles and spaced repetition** built from the mistakes you actually make —
  the natural next step now that `MoveReview` knows what those are.
- **A stronger engine.** The search is honest but modest (a mailbox board and
  legal move generation per node). Bitboards and a staged move generator would
  buy several ply, which mostly matters for the *opponent*, not the coaching.
- **An LLM layer** for free-form questions ("why can't I just take on e5?"),
  answered with the position report as grounding.
- **Import a game** by PGN or FEN and coach through it.
- **Drag-and-drop pieces**, sound, haptics, and an app icon.
