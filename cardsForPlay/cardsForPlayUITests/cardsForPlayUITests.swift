//
//  cardsForPlayUITests.swift
//  cardsForPlayUITests
//
//  Created by 姬翔 on 2026/10/2.
//

import XCTest

final class cardsForPlayUITests: XCTestCase {

  override func setUpWithError() throws {
    // Put setup code here. This method is called before the invocation of each test method in the class.

    // In UI tests it is usually best to stop immediately when a failure occurs.
    continueAfterFailure = false

    // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
  }

  override func tearDownWithError() throws {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
  }

  @MainActor
  func testExample() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-reset-prototype"]
    app.launch()
    XCUIDevice.shared.orientation = .landscapeLeft

    let result = app.otherElements["result-overlay"]
    let discard = app.buttons["discard-button"]

    for _ in 0..<260 where !result.exists {
      let win = app.buttons["action-win"]
      if win.exists && win.isHittable {
        win.tap()
        continue
      }

      let skip = app.buttons["action-skip"]
      if skip.exists && skip.isHittable {
        skip.tap()
        continue
      }

      if discard.exists {
        let tiles = app.buttons.matching(
          NSPredicate(format: "identifier BEGINSWITH 'tile-'")
        )
        let firstTile = tiles.firstMatch
        XCTAssertTrue(firstTile.waitForExistence(timeout: 2))
        firstTile.tap()
        if discard.isEnabled { discard.tap() }
        continue
      }

      _ = discard.waitForExistence(timeout: 1)
    }

    XCTAssertTrue(result.waitForExistence(timeout: 5), "一盘应当以和牌或流局结束")
  }

  @MainActor
  func testLaunchPerformance() throws {
    if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
      // This measures how long it takes to launch your application.
      measure(metrics: [XCTApplicationLaunchMetric()]) {
        XCUIApplication().launch()
      }
    }
  }
}
