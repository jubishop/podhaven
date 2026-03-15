// Copyright Justin Bishop, 2026

import FactoryKit
import Logging
import SwiftUI
import WidgetKit

struct SkipForwardValueProvider: ControlValueProvider {
  private static let log = Log.as(LogSubsystem.Widget.controlCenter)

  var previewValue: Int { 30 }

  func currentValue() async throws -> Int {
    let state = Container.shared.widgetState()
    state.$skipForwardInterval.refresh()
    let interval = state.skipForwardInterval
    Self.log.debug("SkipForwardValueProvider.currentValue: interval=\(interval)")
    return interval
  }
}

struct SkipForwardControl: ControlWidget {
  var body: some ControlWidgetConfiguration {
    StaticControlConfiguration(
      kind: WidgetInfo.skipForwardControlKind,
      provider: SkipForwardValueProvider()
    ) { interval in
      ControlWidgetButton(action: SkipForwardIntent()) {
        AppIcon.seekForward(interval).rawLabel
      }
    }
    .displayName("Skip Forward")
    .description("Skip forward in the current episode.")
  }
}
