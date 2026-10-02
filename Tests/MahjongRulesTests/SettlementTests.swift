import Testing

@testable import MahjongRules

@Suite("报和裁决与零和结算")
struct SettlementTests {
  @Test func selfDrawAndDiscardExamplesMatchRequirements() throws {
    let selfDraw = try Settlement.win(winner: 0, discarder: nil, fan: 10)
    #expect(selfDraw == [54, -18, -18, -18])
    #expect(selfDraw.reduce(0, +) == 0)

    let discard = try Settlement.win(winner: 0, discarder: 2, fan: 10)
    #expect(discard == [34, -8, -18, -8])
    #expect(discard.reduce(0, +) == 0)
  }

  @Test func penaltiesAreSymmetricAndZeroSum() throws {
    let wrong = try Settlement.penalty(offender: 1, amountPerOpponent: 10)
    #expect(wrong == [10, -30, 10, 10])
    #expect(wrong.reduce(0, +) == 0)
    let fraud = try Settlement.penalty(offender: 3, amountPerOpponent: 20)
    #expect(fraud == [20, 20, 20, -60])
    #expect(fraud.reduce(0, +) == 0)
  }

  @Test func rejectsInvalidSeats() {
    #expect(throws: SettlementError.invalidSeat) {
      _ = try Settlement.win(winner: 4, discarder: nil, fan: 8)
    }
    #expect(throws: SettlementError.winnerAndDiscarderMustDiffer) {
      _ = try Settlement.win(winner: 2, discarder: 2, fan: 8)
    }
    #expect(throws: SettlementError.invalidSeat) {
      _ = try Settlement.penalty(offender: -1, amountPerOpponent: 10)
    }
  }

  @Test func adjudicatesFraudWrongWinAndLegalWin() {
    let fraud = context("123m123p123s789s56p", winning: .dot6)
    #expect(WinAdjudicator.adjudicate(fraud) == .fraudulentWin(penaltyPerOpponent: 20))

    let wrong = context("123456m789p234s55p", winning: .dot5, method: .discard)
    #expect(WinAdjudicator.adjudicate(wrong) == .wrongWin(penaltyPerOpponent: 10))

    let legal = context(
      "119m19p19s", honors: [.east, .south, .west, .north, .red, .green, .white],
      winning: .character1)
    guard case let .legal(score) = WinAdjudicator.adjudicate(legal) else {
      Issue.record("Expected a legal thirteen-orphans win")
      return
    }
    #expect(score.isLegalWin)
  }

  @Test func illegalDeclarationSuspendsFutureWinsButKeepsHandActive() {
    var game = GameState(seed: 7)
    let phase = game.phase
    let wrong = context("123456m789p234s55p", winning: .dot5, method: .discard)
    #expect(
      game.adjudicateWinDeclaration(seat: 0, context: wrong) == .wrongWin(penaltyPerOpponent: 10))
    #expect(game.players[0].isWinSuspended)
    #expect(game.phase == phase)
  }

  @Test func everyWinnerDiscarderAndFanCombinationIsZeroSum() throws {
    for winner in 0..<4 {
      for discarder in 0..<4 where discarder != winner {
        for fan in [8, 10, 24, 88, 176] {
          #expect(
            try Settlement.win(winner: winner, discarder: discarder, fan: fan).reduce(0, +) == 0)
        }
      }
      #expect(try Settlement.win(winner: winner, discarder: nil, fan: 88).reduce(0, +) == 0)
    }
  }
}
