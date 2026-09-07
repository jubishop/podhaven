// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Logging

#if !WIDGET_EXTENSION
import UIKit
#endif

#if !WIDGET_EXTENSION && !DEBUG
import MarketplaceKit
#endif

#if !WIDGET_EXTENSION

@MainActor protocol DeviceIdentifying {
  var identifierForVendor: UUID? { get }
}

extension UIDevice: DeviceIdentifying {}

enum AppDistribution: Sendable {
  case appStore
  case testFlight
  case marketplace(String)
  case web
  case other
  case unknown
}

extension Container {
  @MainActor var uiDevice: Factory<any DeviceIdentifying> {
    Factory(self) { UIDevice.current }.scope(.cached)
  }

  var appDistributor: Factory<@concurrent () async throws -> AppDistribution> {
    Factory(self) {
      {
        #if DEBUG
        return .other
        #else
        switch try await AppDistributor.current {
        case .appStore: return .appStore
        case .testFlight: return .testFlight
        case .marketplace(let identifier): return .marketplace(identifier)
        case .web: return .web
        case .other: return .other
        @unknown default: return .unknown
        }
        #endif
      }
    }
    .scope(.cached)
  }
}
#endif

private struct AppInfoState: Sendable {
  let initializeOnce = Once()
  let finalizeOnce = AsyncOnce()
  let deviceIdentifier = ThreadSafe<String>("Unknown")
  #if WIDGET_EXTENSION
  let environment = ThreadSafe<EnvironmentType>(.deployed)
  #else
  let environment = Broadcast(AppInfo.detectEnvironment())
  #endif

  fileprivate init() {}
}

extension Container {
  fileprivate var appInfoState: Factory<AppInfoState> {
    Factory(self) { AppInfoState() }.scope(.cached)
  }
}

enum EnvironmentType: String {
  case appStore
  case iPhoneDev
  case macDev
  case preview
  case simulator
  case testFlight
  case testing
  case deployed

  // `.deployed` is a release build whose distribution channel hasn't been
  // refined to `.appStore` / `.testFlight` yet.
  var isRelease: Bool {
    switch self {
    case .deployed, .appStore, .testFlight: true
    case .iPhoneDev, .macDev, .preview, .simulator, .testing: false
    }
  }

  var allowsDiagnostics: Bool {
    switch self {
    case .appStore, .deployed: false
    case .iPhoneDev, .macDev, .preview, .simulator, .testFlight, .testing: true
    }
  }
}

enum AppInfo {
  private static let log = Log.as("AppInfo")
  private static var state: AppInfoState { Container.shared.appInfoState() }

  // MARK: - System Settings

  #if !WIDGET_EXTENSION
  static func openSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    Task { @MainActor in Container.shared.uiApplication().open(url) }
  }
  #endif

  // MARK: - Environment Info

  static var deviceIdentifier: String { state.deviceIdentifier() }
  static var myDevice: Bool { deviceIdentifier == "6B915F57-D7FC-4249-8FAD-B71F5D362CEB" }

  // The widget extension never calls `initializeEnvironment`, so inside the
  // widget process `environment` stays `.deployed` forever — don't branch
  // widget behavior on this value.
  #if WIDGET_EXTENSION
  static var environment: EnvironmentType {
    set { state.environment(newValue) }
    get { state.environment() }
  }
  #else
  static var environment: EnvironmentType {
    set { state.environment.new(newValue) }
    get { state.environment.current }
  }
  #endif

  #if !WIDGET_EXTENSION
  @MainActor static func initializeEnvironment() {
    state.initializeOnce.run {
      state.deviceIdentifier(
        Container.shared.uiDevice().identifierForVendor?.uuidString ?? "Unknown"
      )
      environment = detectEnvironment()
    }
  }
  #endif

  #if !WIDGET_EXTENSION
  static func finalizeEnvironment() async {
    await state.finalizeOnce.run {
      guard environment == .deployed else { return }
      do {
        let refined: EnvironmentType
        switch try await Container.shared.appDistributor()() {
        case .appStore:
          refined = .appStore
        case .testFlight:
          refined = .testFlight
        case .marketplace(let identifier):
          log.notice(
            "Distributed via marketplace \(identifier); treating as App Store for debug gating"
          )
          refined = .appStore
        case .web:
          log.notice("AppDistributor.web; treating as App Store for debug gating")
          refined = .appStore
        case .other:
          log.notice("AppDistributor.other; treating as App Store for debug gating")
          refined = .appStore
        case .unknown:
          log.warning("Unknown AppDistributor; treating as App Store for debug gating")
          refined = .appStore
        }
        log.debug("Environment refined to \(refined)")
        environment = refined
      } catch {
        log.caughtError(
          "finalizeEnvironment: AppDistributor.current failed; defaulting to .appStore",
          error
        )
        environment = .appStore
      }
    }
  }
  #endif

  fileprivate static func detectEnvironment() -> EnvironmentType {
    let env = ProcessInfo.processInfo.environment
    guard env["XCODE_RUNNING_FOR_PREVIEWS"] != "1",
      env["XCODE_RUNNING_FOR_PLAYGROUNDS"] != "1"
    else { return .preview }

    guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    else { return .testing }

    #if targetEnvironment(simulator)
    return .simulator
    #else
    #if DEBUG
    return currentDevelopmentEnvironment()
    #else
    // Refined async by `finalizeEnvironment()` once `AppDistributor.current` resolves.
    return .deployed
    #endif
    #endif
  }

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
        level: .info
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
    guard let identifier = Bundle.main.bundleIdentifier else {
      Assert.fatal("Bundle.main.bundleIdentifier is nil")
    }
    return identifier
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

  static let logMaxFileSizeBytes = 4_000_000
  static let logTargetFileSizeBytes = 3_000_000

  static let recentLogMaxFileSizeBytes = 128 * 1024
  static let recentLogTargetFileSizeBytes = recentLogMaxFileSizeBytes * 3 / 4

  static var recentLogFileURL: URL {
    documentsDirectory.appendingPathComponent("recent-log.ndjson")
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
