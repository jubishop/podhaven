// Copyright Justin Bishop, 2026

import FactoryKit
import UIKit

extension Container {
  @MainActor var uiApplication: Factory<any ApplicationProviding> {
    Factory(self) { UIApplication.shared }
  }
}

extension UIApplication: ApplicationProviding {}
