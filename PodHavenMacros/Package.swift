// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import CompilerPluginSupport
import PackageDescription

let swiftSettings: [SwiftSetting] = [
  .swiftLanguageMode(.v6),
  .enableUpcomingFeature("ExistentialAny"),
  .enableUpcomingFeature("InternalImportsByDefault"),
  .enableUpcomingFeature("MemberImportVisibility"),
  .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
  .enableUpcomingFeature("InferIsolatedConformances"),
]

// Tests opt out of the stylistic upcoming flags, matching the app target.
let testSwiftSettings: [SwiftSetting] = [
  .swiftLanguageMode(.v6),
  .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
  .enableUpcomingFeature("InferIsolatedConformances"),
]

let package = Package(
  name: "PodHavenMacros",
  platforms: [
    .macOS(.v15),
    .iOS(.v18),
  ],
  products: [
    .library(
      name: "SavedMacro",
      targets: ["SavedMacro"]
    )
  ],
  dependencies: [
    .package(url: "https://github.com/swiftlang/swift-syntax", branch: "main"),
    .package(url: "https://github.com/pointfreeco/swift-tagged", branch: "main"),
    .package(url: "https://github.com/apple/swift-testing", branch: "main"),
  ],
  targets: [
    .macro(
      name: "SavedMacroPlugin",
      dependencies: [
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
        .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
      ],
      swiftSettings: swiftSettings
    ),
    .target(
      name: "SavedMacro",
      dependencies: [
        "SavedMacroPlugin",
        .product(name: "Tagged", package: "swift-tagged"),
      ],
      swiftSettings: swiftSettings
    ),
    .testTarget(
      name: "SavedMacroPluginTests",
      dependencies: [
        "SavedMacroPlugin",
        .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
        .product(name: "Testing", package: "swift-testing"),
      ],
      swiftSettings: testSwiftSettings
    ),
  ]
)
