// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "MahjongRules",
  platforms: [.macOS(.v13), .iOS(.v17)],
  products: [
    .library(name: "MahjongRules", targets: ["MahjongRules"]),
    .library(name: "MahjongAI", targets: ["MahjongAI"]),
  ],
  targets: [
    .target(name: "MahjongRules"),
    .target(name: "MahjongAI", dependencies: ["MahjongRules"]),
    .testTarget(name: "MahjongRulesTests", dependencies: ["MahjongRules"]),
    .testTarget(name: "MahjongAITests", dependencies: ["MahjongAI", "MahjongRules"]),
  ]
)
