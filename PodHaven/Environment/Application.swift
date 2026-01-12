// Copyright Justin Bishop, 2026

import FactoryKit
import UIKit

extension Container {
  var uiApplication: Factory<any ApplicationProviding> {
    Factory(self) { @MainActor in UIApplication.shared }.scope(.cached)
  }
}

extension UIApplication: ApplicationProviding {}
