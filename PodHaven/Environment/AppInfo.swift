// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Logging

#if !WIDGET_EXTENSION
import StoreKit
#endif

enum EnvironmentType: String {
  case appStore
  case iPhoneDev
  case macDev
  case preview
  case simulator
  case testFlight
  case testing
}

enum AppInfo {
  private static let log = Log.as("AppInfo")

  // MARK: - System Settings

  #if !WIDGET_EXTENSION
  static func openSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    Task { @MainActor in Container.shared.uiApplication().open(url) }
  }
  #endif

  // MARK: - Environment Info

  private static let myDeviceIDs: Set<String> = [
    "F73227BB-6F74-4E94-B993-4765E5633FA5", // iPhoneDev
    "48850004-711A-4B96-B6A4-588689CF3609",  // testFlight
  ]

  private static let _deviceIdentifier = ThreadSafe<String>("Unknown")
  static var deviceIdentifier: String { _deviceIdentifier() }

  static var myDevice: Bool { myDeviceIDs.contains(deviceIdentifier) }

  private static let _environment = ThreadSafe<EnvironmentType>(.appStore)
  static var environment: EnvironmentType {
    set { _environment(newValue) }
    get { _environment() }
  }

  #if !WIDGET_EXTENSION
  @MainActor static func initializeEnvironment() {
    guard Function.neverCalled() else { return }

    _deviceIdentifier(UIDevice.current.identifierForVendor?.uuidString ?? "Unknown")
    environment = detectEnvironment()
  }
  #endif

  #if !WIDGET_EXTENSION
  // Asynchronous environment refinement using AppTransactions
  static func finalizeEnvironment() async {
    guard Function.neverCalled() else { return }

    // Only refine environment for release builds on real devices
    #if !DEBUG && !targetEnvironment(simulator)
    do {
      let result = try await AppTransaction.shared
      if let refinedEnvironment = appTransactionEnvironment(for: result),
        environment != refinedEnvironment
      {
        log.debug("Environment refined to \(refinedEnvironment)")
        environment = refinedEnvironment
      }
    } catch {
      log.caughtError("finalizeEnvironment: AppTransaction.shared failed", error)

      // Retry with refresh
      do {
        let refreshed = try await AppTransaction.refresh()
        if let refinedEnvironment = appTransactionEnvironment(for: refreshed),
          environment != refinedEnvironment
        {
          log.debug("Environment refined to \(refinedEnvironment) after refresh")
          environment = refinedEnvironment
        }
      } catch {
        log.caughtError("finalizeEnvironment: AppTransaction.refresh also failed", error)
        // Keep existing environment
      }
    }
    #endif
  }
  #endif

  // Initial synchronous environment detection
  private static func detectEnvironment() -> EnvironmentType {
    guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1"
    else { return .preview }

    guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    else { return .testing }

    #if targetEnvironment(simulator)
    return .simulator
    #else
    #if DEBUG
    return currentDevelopmentEnvironment()
    #else
    // default to appStore: finalizeEnvironment() will refine this
    return myDevice ? currentDevelopmentEnvironment() : .appStore
    #endif
    #endif
  }

  #if !WIDGET_EXTENSION
  private static func appTransactionEnvironment(
    for verificationResult: VerificationResult<AppTransaction>
  ) -> EnvironmentType? {
    switch verificationResult {
    case .verified(let appTransaction):
      switch appTransaction.environment {
      case .sandbox:
        return .testFlight
      case .production:
        return .appStore
      default:
        log.warning(
          "Unknown App Store transaction environment: \(appTransaction.environment)"
        )
        return nil
      }
    case .unverified(_, _):
      log.warning("Unable to verify App Store transaction for environment detection")
      return nil
    }
  }
  #endif

  private static func currentDevelopmentEnvironment() -> EnvironmentType {
    (ProcessInfo.processInfo.isMacCatalystApp || ProcessInfo.processInfo.isiOSAppOnMac)
      ? .macDev : .iPhoneDev
  }

  static var countryCode: String {
    Locale.current.region?.identifier.lowercased() ?? "us"
  }

  static var languageCode: String? {
    Locale.current.language.languageCode?.identifier
  }

  // MARK: - Build Info

  static var version: String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
  }

  static var buildNumber: String {
    Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
  }

  static var gitCommitHash: String {
    Bundle.main.infoDictionary?["GitCommitHash"] as? String ?? "Unknown"
  }

  static var buildDate: Date {
    guard let infoPath = Bundle.main.path(forResource: "Info", ofType: "plist")
    else {
      log.warning("Info.plist not found, returning current date as buildDate")
      return Date()
    }

    do {
      let infoAttr = try FileManager.default.attributesOfItem(atPath: infoPath)
      if let infoDate = infoAttr[FileAttributeKey.creationDate] as? Date {
        return infoDate
      }
      log.warning("Info.plist has no creationDate attribute, returning current date as buildDate")
      return Date()
    } catch {
      log.caughtError(
        "Failed to read Info.plist attributes at \(infoPath)",
        error,
        remarkable: .info
      )
      return Date()
    }
  }

  // MARK: - Data Storage

  static var appGroupID: String {
    guard let groupID = Bundle.main.infoDictionary?["AppGroupID"] as? String else {
      Assert.fatal("AppGroupID not found in Info.plist")
    }
    return groupID
  }

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
    do {
      try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
    } catch {
      Assert.fatal("Failed to create documents directory at \(dataDir): \(error)")
    }

    return dataDir
  }

  static var logFileURL: URL {
    documentsDirectory.appendingPathComponent("log.ndjson")
  }

  static var applicationSupportDirectory: URL {
    let baseURL = URL.applicationSupportDirectory

    // Production uses root Documents directory to preserve existing data
    guard let subdirectory = dataDirectoryName
    else { return baseURL }

    // Development builds use subdirectories
    let dataDir = baseURL.appendingPathComponent(subdirectory)
    do {
      try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
    } catch {
      Assert.fatal("Failed to create application support directory at \(dataDir): \(error)")
    }

    return dataDir
  }
}
