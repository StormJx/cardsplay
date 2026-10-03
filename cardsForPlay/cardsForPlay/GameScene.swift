import SpriteKit

final class GameScene: SKScene {
  var tableStyle = "table-wood"

  override func didMove(to view: SKView) {
    anchorPoint = CGPoint(x: 0.5, y: 0.5)
    rebuildTable()
  }

  func applyTable(_ style: String) {
    tableStyle = style
    if childNode(withName: "felt") == nil {
      return
    }
    paint()
  }

  private func rebuildTable() {
    removeAllChildren()
    let table = SKShapeNode(
      rectOf: CGSize(width: size.width * 0.64, height: size.height * 0.52),
      cornerRadius: 34
    )
    table.name = "felt"
    table.lineWidth = 5
    addChild(table)

    let center = SKShapeNode(rectOf: CGSize(width: 130, height: 130), cornerRadius: 18)
    center.fillColor = SKColor(white: 0.06, alpha: 0.5)
    center.strokeColor = SKColor(white: 1, alpha: 0.2)
    center.run(
      .repeatForever(
        .sequence([
          .fadeAlpha(to: 0.65, duration: 1.4),
          .fadeAlpha(to: 1, duration: 1.4),
        ])))
    addChild(center)
    paint()
  }

  private func paint() {
    let palette = Self.palette(tableStyle)
    backgroundColor = palette.room
    guard let table = childNode(withName: "felt") as? SKShapeNode else { return }
    table.fillColor = palette.felt
    table.strokeColor = palette.rim
  }

  private static func palette(_ style: String) -> (room: SKColor, felt: SKColor, rim: SKColor) {
    switch style {
    case "table-city":
      return (
        SKColor(red: 0.04, green: 0.06, blue: 0.14, alpha: 1),
        SKColor(red: 0.10, green: 0.16, blue: 0.32, alpha: 1),
        SKColor(red: 0.55, green: 0.64, blue: 0.82, alpha: 0.7)
      )
    case "table-lake":
      return (
        SKColor(red: 0.03, green: 0.16, blue: 0.20, alpha: 1),
        SKColor(red: 0.07, green: 0.40, blue: 0.42, alpha: 1),
        SKColor(red: 0.70, green: 0.78, blue: 0.52, alpha: 0.65)
      )
    case "table-final":
      return (
        SKColor(red: 0.12, green: 0.03, blue: 0.05, alpha: 1),
        SKColor(red: 0.30, green: 0.08, blue: 0.12, alpha: 1),
        SKColor(red: 0.80, green: 0.64, blue: 0.28, alpha: 0.75)
      )
    default:
      return (
        SKColor(red: 0.035, green: 0.25, blue: 0.17, alpha: 1),
        SKColor(red: 0.06, green: 0.38, blue: 0.25, alpha: 1),
        SKColor(red: 0.76, green: 0.62, blue: 0.34, alpha: 0.55)
      )
    }
  }
}
