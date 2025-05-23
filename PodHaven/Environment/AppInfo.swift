// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import StoreKit

extension Container {
  var appInfo: Factory<AppInfo> {
    Factory(self) { AppInfo() }.scope(.cached)
  }
}

enum EnvironmentType: String {
  case appStore
  case onMac
  case onIPhone
  case preview
  case simulator

  var inDebugger: Bool {
    switch self {
    case .preview, .simulator:
      return true
    default:
      return false
    }
  }

  var onDevice: Bool {
    switch self {
    case .onIPhone, .appStore, .onMac:
      return true
    default:
      return false
    }
  }
}

final actor AppInfo: Sendable {
  // MARK: - Environment Info

  private var _environment: EnvironmentType?
  var environment: EnvironmentType {
    get async {
      if let environment = _environment {
        return environment
      }
      let environment = await _getEnvironment()
      _environment = environment
      return environment
    }
  }

  // MARK: - Private Helpers

  private func _getEnvironment() async -> EnvironmentType {
    if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
      return .preview
    }

    #if targetEnvironment(simulator)
    return .simulator
    #else
    do {
      let result = try await AppTransaction.shared
      switch result {
      case .verified(let appTransaction):
        switch appTransaction.environment {
        case .sandbox:
          return .onIPhone
        case .production:
          return .appStore
        default:
          Assert.fatal("AppTransaction environment is actually \(appTransaction.environment)")
        }
      case .unverified(_, _):
        Assert.fatal("Could not verify appTransaction")
      }
    } catch {
      return .onMac
    }
    #endif
  }
}
