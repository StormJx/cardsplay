import MahjongRules

/// One East-round: four hands, prevailing wind stays East.
/// With repeat-dealer off, the dealer moves on after every hand, including a draw.
public enum EastRound {
  public static let handCount = 4
  public static let roundWind = Wind.east

  /// How the hand ended, for the next dealer only. Scores are unchanged.
  public enum Continuation: Equatable, Sendable {
    case win(Int)
    case draw
  }

  public static func dealer(handIndex: Int, initialDealer: Int) -> Int {
    let start = ((initialDealer % 4) + 4) % 4
    return (start + max(0, handIndex)) % 4
  }

  /// Next dealer. `repeats` stays with a winning dealer and, as in common MCR play, also stays after a draw.
  /// Off, the seat always passes, including after a draw. The hand count does not grow.
  public static func nextDealer(current: Int, continuation: Continuation, repeats: Bool) -> Int {
    let seat = ((current % 4) + 4) % 4
    guard repeats else { return (seat + 1) % 4 }
    switch continuation {
    case .draw:
      return seat
    case .win(let winner):
      let winnerSeat = ((winner % 4) + 4) % 4
      return winnerSeat == seat ? seat : (seat + 1) % 4
    }
  }

  /// Wind of a fixed screen seat while `dealer` is East.
  public static func seatWind(seat: Int, dealer: Int) -> Wind {
    Wind(rawValue: (seat - dealer + 4) % 4)!
  }

  public static func isFinalHand(_ handIndex: Int) -> Bool {
    handIndex >= handCount - 1
  }

  public static func accumulate(_ totals: [Int], _ deltas: [Int]) -> [Int] {
    precondition(totals.count == 4 && deltas.count == 4)
    return zip(totals, deltas).map(+)
  }
}

/// East, South, West, and North: sixteen hands. No extra hand is added when the dealer repeats.
public enum FullMatch {
  public static let roundCount = 4
  public static let handsPerRound = EastRound.handCount
  public static let handCount = roundCount * handsPerRound
  public static let winds: [Wind] = [.east, .south, .west, .north]

  public static func roundIndex(handIndex: Int) -> Int {
    min(roundCount - 1, max(0, handIndex) / handsPerRound)
  }

  public static func roundWind(handIndex: Int) -> Wind {
    winds[roundIndex(handIndex: handIndex)]
  }

  public static func handInRound(handIndex: Int) -> Int {
    (max(0, handIndex) % handsPerRound) + 1
  }

  public static func dealer(handIndex: Int, initialDealer: Int) -> Int {
    EastRound.dealer(handIndex: handIndex, initialDealer: initialDealer)
  }

  public static func nextDealer(
    current: Int, continuation: EastRound.Continuation, repeats: Bool
  ) -> Int {
    EastRound.nextDealer(current: current, continuation: continuation, repeats: repeats)
  }

  public static func seatWind(seat: Int, dealer: Int) -> Wind {
    EastRound.seatWind(seat: seat, dealer: dealer)
  }

  public static func isFinalHand(_ handIndex: Int) -> Bool {
    handIndex >= handCount - 1
  }

  /// 1 is the best score. Equal scores share a rank.
  public static func ranks(_ scores: [Int]) -> [Int] {
    scores.map { score in scores.filter { $0 > score }.count + 1 }
  }
}
