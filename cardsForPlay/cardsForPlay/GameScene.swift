//
//  GameScene.swift
//  cardsForPlay
//
//  Created by 姬翔 on 2026/10/2.
//

import SpriteKit

final class GameScene: SKScene {
  override func didMove(to view: SKView) {
    backgroundColor = SKColor(red: 0.035, green: 0.25, blue: 0.17, alpha: 1)
    anchorPoint = CGPoint(x: 0.5, y: 0.5)

    let table = SKShapeNode(
      rectOf: CGSize(width: size.width * 0.64, height: size.height * 0.52),
      cornerRadius: 34
    )
    table.fillColor = SKColor(red: 0.06, green: 0.38, blue: 0.25, alpha: 1)
    table.strokeColor = SKColor(red: 0.76, green: 0.62, blue: 0.34, alpha: 0.55)
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
  }
}
