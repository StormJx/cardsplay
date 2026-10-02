public enum WinDeclaration: Equatable, Sendable {
  case legal(ScoreResult)
  case wrongWin(penaltyPerOpponent: Int)
  case fraudulentWin(penaltyPerOpponent: Int)
}
public enum WinAdjudicator {
  public static func adjudicate(_ context: WinContext) -> WinDeclaration {
    guard WinningAnalyzer.hasWinningStructure(context) else {
      return .fraudulentWin(penaltyPerOpponent: 20)
    }
    guard let score = MCRScorer.score(context), score.isLegalWin else {
      return .wrongWin(penaltyPerOpponent: 10)
    }
    return .legal(score)
  }
}
public enum SettlementError: Error, Equatable {
  case invalidSeat
  case winnerAndDiscarderMustDiffer
}
public enum Settlement {
  /// Returns four zero-sum score deltas in east/south/west/north seat order.
  public static func win(winner: Int, discarder: Int?, fan: Int) throws -> [Int] {
    guard (0..<4).contains(winner), discarder.map({ (0..<4).contains($0) }) ?? true else {
      throw SettlementError.invalidSeat
    }
    if discarder == winner { throw SettlementError.winnerAndDiscarderMustDiffer }
    var deltas = Array(repeating: 0, count: 4)
    if let discarder {
      for seat in 0..<4 where seat != winner {
        let payment = seat == discarder ? 8 + fan : 8
        deltas[seat] -= payment
        deltas[winner] += payment
      }
    } else {
      for seat in 0..<4 where seat != winner {
        let payment = 8 + fan
        deltas[seat] -= payment
        deltas[winner] += payment
      }
    }
    return deltas
  }

  public static func penalty(offender: Int, amountPerOpponent: Int) throws -> [Int] {
    guard (0..<4).contains(offender) else { throw SettlementError.invalidSeat }
    var deltas = Array(repeating: amountPerOpponent, count: 4)
    deltas[offender] = -amountPerOpponent * 3
    return deltas
  }
}
