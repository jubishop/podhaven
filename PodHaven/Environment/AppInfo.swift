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

  static var isDebug: Bool {
    #if DEBUG
    true
    #else
    false
    #endif
  }

  static var isPreview: Bool {
    ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
  }

  static var isSimulator: Bool {
    #if targetEnvironment(simulator)
    true
    #else
    false
    #endif
  }

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
    if Self.isPreview { return .preview }
    if Self.isSimulator { return .simulator }

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
  }
}
