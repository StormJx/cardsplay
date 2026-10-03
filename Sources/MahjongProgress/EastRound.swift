import MahjongRules

/// One East-round: four hands, prevailing wind stays East, the dealer moves on after every hand.
public enum EastRound {
  public static let handCount = 4
  public static let roundWind = Wind.east

  public static func dealer(handIndex: Int, initialDealer: Int) -> Int {
    let start = ((initialDealer % 4) + 4) % 4
    return (start + max(0, handIndex)) % 4
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

/// East, South, West, and North: sixteen hands. No repeat-dealer extra hand.
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
