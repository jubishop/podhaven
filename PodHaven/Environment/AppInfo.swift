// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Security
import StoreKit

enum EnvironmentType: String {
  case appStore
  case iPhoneDev
  case macDev
  case preview
  case simulator
  case testFlight
  case testing
}

actor AppInfo {
  private static let log = Log.as("AppInfo")

  // MARK: - Environment Info

  private static let key = "com.artisanalsoftware.PodHaven"
  private static let myDeviceIDs: Set = [
    "6A13E21C-AFFB-43C9-9491-C9F3AF1DB6B1",  // testFlight
    "CC7A8EBE-0CC3-45DE-87A2-65B425F164DB",  // iPhoneDev
    "B290299A-7693-4F5B-AF94-14E6C6279A84",  // macDev
  ]

  static var deviceIdentifier: String {
    guard let uuid = KeychainHelper.get(forKey: key) else {
      let newUUID = UUID().uuidString
      KeychainHelper.set(newUUID, forKey: key)
      return newUUID
    }
    return uuid
  }

  static var myDevice: Bool { myDeviceIDs.contains(deviceIdentifier) }

  static var environment: EnvironmentType = .appStore

  static func initializeEnvironment() async {
    environment = await _getEnvironment()
  }

  private static func _getEnvironment() async -> EnvironmentType {
    if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" { return .preview }

    if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return .testing }

    #if targetEnvironment(simulator)
    return .simulator
    #else

    do {
      let result = try await AppTransaction.shared
      switch result {
      case .verified(let appTransaction):
        switch appTransaction.environment {
        case .sandbox:
          return .testFlight
        case .production:
          return .appStore
        default:
          Assert.fatal("AppTransaction environment is actually \(appTransaction.environment)")
        }
      case .unverified(_, _):
        Assert.fatal("Could not verify appTransaction")
      }
    } catch {
      // AppTransaction.shared throws for Xcode-installed apps
      return (ProcessInfo.processInfo.isMacCatalystApp || ProcessInfo.processInfo.isiOSAppOnMac)
        ? .macDev : .iPhoneDev
    }
    #endif
  }

  // MARK: - Build Info

  static var version: String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
  }

  static var buildNumber: String {
    Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
  }

  static var buildDate: Date {
    if let infoPath = Bundle.main.path(forResource: "Info", ofType: "plist"),
      let infoAttr = try? FileManager.default.attributesOfItem(atPath: infoPath),
      let infoDate = infoAttr[FileAttributeKey.creationDate] as? Date
    {
      return infoDate
    }
    return Date()
  }

  // MARK: - Data Storage

  static var bundleIdentifier: String {
    Bundle.main.bundleIdentifier ?? "com.artisanalsoftware.PodHaven"
  }

  static var dataDirectoryName: String? {
    switch bundleIdentifier {
    case "com.artisanalsoftware.PodHaven.dev":
      return "PodHavenDev"
    case "com.artisanalsoftware.PodHaven.debug":
      return "PodHavenDebug"
    default:
      return nil  // Use root Documents directory for production
    }
  }

  static var documentsDirectory: URL {
    let baseURL = URL.documentsDirectory

    // Production uses root Documents directory to preserve existing data
    guard let subdirectory = dataDirectoryName
    else { return baseURL }

    // Development builds use subdirectories
    let dataDir = baseURL.appendingPathComponent(subdirectory)
    try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)

    return dataDir
  }

  static var applicationSupportDirectory: URL {
    let baseURL = URL.applicationSupportDirectory

    // Production uses root Documents directory to preserve existing data
    guard let subdirectory = dataDirectoryName
    else { return baseURL }

    // Development builds use subdirectories
    let dataDir = baseURL.appendingPathComponent(subdirectory)
    try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)

    return dataDir
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
