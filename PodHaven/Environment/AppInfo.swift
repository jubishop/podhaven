// Copyright Justin Bishop, 2025

import Foundation
import StoreKit

enum EnvironmentType: String {
  case appStore
  case mac
  case iPhone
  case preview
  case simulator
}

final actor AppInfo: Sendable {
  // MARK: - Environment Info

  static var environment: EnvironmentType = .appStore

  static func initializeEnvironment() async {
    environment = await _getEnvironment()
  }

  private static func _getEnvironment() async -> EnvironmentType {
    if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" { return .preview }

    #if targetEnvironment(simulator)
    return .simulator
    #else
    do {
      let result = try await AppTransaction.shared
      switch result {
      case .verified(let appTransaction):
        switch appTransaction.environment {
        case .sandbox:
          return .iPhone
        case .production:
          return .appStore
        default:
          Assert.fatal("AppTransaction environment is actually \(appTransaction.environment)")
        }
      case .unverified(_, _):
        Assert.fatal("Could not verify appTransaction")
      }
    } catch {
      return .mac
    }
    #endif
  }
}
