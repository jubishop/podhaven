// Copyright Justin Bishop, 2026

import WidgetKit

protocol ControlReloading {
  func reloadControls(ofKind kind: String)
}

extension ControlCenter: ControlReloading {}
