// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import SwiftUI

@Observable @MainActor final class SettingsViewModel {
  @ObservationIgnored @DynamicInjected(\.appInfo) private var appInfo

  // MARK: - State Management

  var currentEnvironment = EnvironmentType.appStore

  // MARK: - Initialization

  init() {}

  func execute() async {
    currentEnvironment = await appInfo.environment
  }
}
