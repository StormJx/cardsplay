// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "MahjongRules",
  platforms: [.macOS(.v13), .iOS(.v17)],
  products: [
    .library(name: "MahjongRules", targets: ["MahjongRules"]),
    .library(name: "MahjongAI", targets: ["MahjongAI"]),
    .library(name: "MahjongProgress", targets: ["MahjongProgress"]),
  ],
  targets: [
    .target(name: "MahjongRules"),
    .target(name: "MahjongAI", dependencies: ["MahjongRules"]),
    .target(name: "MahjongProgress", dependencies: ["MahjongRules", "MahjongAI"]),
    .testTarget(name: "MahjongRulesTests", dependencies: ["MahjongRules"]),
    .testTarget(name: "MahjongAITests", dependencies: ["MahjongAI", "MahjongRules"]),
    .testTarget(name: "MahjongProgressTests", dependencies: ["MahjongProgress"]),
  ]
)
