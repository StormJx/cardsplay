// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "MahjongRules",
  platforms: [.macOS(.v13), .iOS(.v17)],
  products: [
    .library(name: "MahjongRules", targets: ["MahjongRules"])
  ],
  targets: [
    .target(name: "MahjongRules"),
    .testTarget(name: "MahjongRulesTests", dependencies: ["MahjongRules"]),
  ]
)
