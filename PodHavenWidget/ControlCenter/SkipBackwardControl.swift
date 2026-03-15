// Copyright Justin Bishop, 2026

import FactoryKit
import Logging
import SwiftUI
import WidgetKit

struct SkipBackwardValueProvider: ControlValueProvider {
  private static let log = Log.as(LogSubsystem.Widget.controlCenter)

  var previewValue: Int { 15 }

  func currentValue() async throws -> Int {
    let state = Container.shared.widgetState()
    state.$skipBackwardInterval.refresh()
    let interval = state.skipBackwardInterval
    Self.log.debug("SkipBackwardValueProvider.currentValue: interval=\(interval)")
    return interval
  }
}

struct SkipBackwardControl: ControlWidget {
  var body: some ControlWidgetConfiguration {
    StaticControlConfiguration(
      kind: WidgetInfo.skipBackwardControlKind,
      provider: SkipBackwardValueProvider()
    ) { interval in
      ControlWidgetButton(action: SkipBackwardIntent()) {
        AppIcon.seekBackward(interval).rawLabel
      }
    }
    .displayName("Skip Backward")
    .description("Skip backward in the current episode.")
  }
}
