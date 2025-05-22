// Copyright Justin Bishop, 2025

import Foundation
import StoreKit

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

enum AppEnvironment {
  static var current: EnvironmentType {
    get async {
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
}
