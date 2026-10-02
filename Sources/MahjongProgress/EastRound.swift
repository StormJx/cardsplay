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
