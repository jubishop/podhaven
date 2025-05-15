// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import CompilerPluginSupport

let package = Package(
  name: "PodHavenMacros",
  platforms: [
    .macOS(.v15),
    .iOS(.v18),
  ],
  products: [
    .library(
      name: "GRDBSavedMacro",
      targets: ["GRDBSavedMacro"]
    ),
  ],
  dependencies: [
    .package(url: "https://github.com/swiftlang/swift-syntax", branch: "main"),
    .package(url: "https://github.com/pointfreeco/swift-tagged", branch: "main"),
    .package(url: "https://github.com/apple/swift-testing", branch: "main"),
  ],
  targets: [
    .macro(
      name: "GRDBSavedMacroPlugin",
      dependencies: [
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
        .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
      ]
    ),
    .target(
      name: "GRDBSavedMacro",
      dependencies: [
        "GRDBSavedMacroPlugin",
        .product(name: "Tagged", package: "swift-tagged")
      ]
    ),
    .testTarget(
      name: "GRDBSavedMacroPluginTests",
      dependencies: [
        "GRDBSavedMacro",
        "GRDBSavedMacroPlugin",
        .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
        .product(name: "Testing", package: "swift-testing")
      ]
    ),
  ]
)
