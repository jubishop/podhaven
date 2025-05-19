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
      name: "ReadableErrorMacro",
      targets: ["ReadableErrorMacro"]
    ),
    .library(
      name: "SavedMacro",
      targets: ["SavedMacro"]
    ),
  ],
  dependencies: [
    .package(url: "https://github.com/swiftlang/swift-syntax", branch: "main"),
    .package(url: "https://github.com/pointfreeco/swift-tagged", branch: "main"),
    .package(url: "https://github.com/apple/swift-testing", branch: "main"),
  ],
  targets: [
    .macro(
      name: "ReadableErrorMacroPlugin",
      dependencies: [
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
        .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
      ]
    ),
    .target(
      name: "ReadableErrorMacro",
      dependencies: [
        "ReadableErrorMacroPlugin"
      ]
    ),
    .macro(
      name: "SavedMacroPlugin",
      dependencies: [
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
        .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
      ]
    ),
    .target(
      name: "SavedMacro",
      dependencies: [
        "SavedMacroPlugin",
        .product(name: "Tagged", package: "swift-tagged")
      ]
    ),
    .testTarget(
      name: "ReadableErrorMacroPluginTests",
      dependencies: [
        "ReadableErrorMacro",
        "ReadableErrorMacroPlugin",
        .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
        .product(name: "Testing", package: "swift-testing")
      ]
    ),
    .testTarget(
      name: "SavedMacroPluginTests",
      dependencies: [
        "SavedMacro",
        "SavedMacroPlugin",
        .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
        .product(name: "Testing", package: "swift-testing")
      ]
    ),
  ]
)
