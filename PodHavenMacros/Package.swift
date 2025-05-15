// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import CompilerPluginSupport

let package = Package(
  name: "PodHavenMacros",
  platforms: [
    .macOS(.v13),
    .iOS(.v16),
  ],
  products: [
    .library(
      name: "SavedMacros",
      targets: ["SavedMacros"]
    ),
  ],
  dependencies: [
    .package(url: "https://github.com/swiftlang/swift-syntax", branch: "main"),
    .package(url: "https://github.com/pointfreeco/swift-tagged", branch: "main"),
  ],
  targets: [
    .macro(
      name: "SavedMacrosPlugin",
      dependencies: [
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
        .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
      ]
    ),
    .target(
      name: "SavedMacros",
      dependencies: [
        "SavedMacrosPlugin",
        .product(name: "Tagged", package: "swift-tagged")
      ]
    ),
    .testTarget(
      name: "SavedMacrosPluginTests",
      dependencies: [
        "SavedMacrosPlugin",
        .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax")
      ]
    ),
  ]
)
