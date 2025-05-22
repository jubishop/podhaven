// Copyright Justin Bishop, 2025 

import Foundation
import SwiftUI

@Observable @MainActor final class SettingsViewModel {
  // MARK: - State Management

  var currentEnvironment = EnvironmentType.appStore

  // MARK: - Initialization

  init() {
  }

  func execute() async {
    currentEnvironment = await AppEnvironment.current
  }
}
