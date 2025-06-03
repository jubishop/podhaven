// Copyright Justin Bishop, 2025

import Foundation
import Security
import StoreKit

enum EnvironmentType: String {
  case appStore
  case mac
  case iPhone
  case preview
  case simulator
}

actor AppInfo {
  private static let log = Log.as("appInfo")

  // MARK: - Environment Info

  private static let key = "com.artisanalsoftware.PodHaven"
  private static let myDeviceID = "6A13E21C-AFFB-43C9-9491-C9F3AF1DB6B1"

  static var deviceIdentifier: String {
    guard let uuid = KeychainHelper.get(forKey: key) else {
      let newUUID = UUID().uuidString
      KeychainHelper.set(newUUID, forKey: key)
      return newUUID
    }
    return uuid
  }

  static var myPhone: Bool { deviceIdentifier == myDeviceID }

  static var environment: EnvironmentType = .appStore

  static func initializeEnvironment() async {
    environment = await _getEnvironment()
    log.debug("AppInfo.environment is: \(AppInfo.environment)")
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

private class KeychainHelper {
  static func get(forKey key: String) -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: key,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]

    var dataTypeRef: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

    if status == errSecSuccess,
      let retrievedData = dataTypeRef as? Data,
      let value = String(data: retrievedData, encoding: .utf8)
    {
      return value
    }

    return nil
  }

  static func set(_ value: String, forKey key: String) {
    if let existingValue = get(forKey: key) {
      if existingValue == value {
        return
      } else {
        delete(forKey: key)
      }
    }

    if let data = value.data(using: .utf8) {
      let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrAccount as String: key,
        kSecValueData as String: data,
      ]

      SecItemAdd(query as CFDictionary, nil)
    }
  }

  static func delete(forKey key: String) {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: key,
    ]

    SecItemDelete(query as CFDictionary)
  }
}
