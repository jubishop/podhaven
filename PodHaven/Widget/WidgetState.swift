// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation

extension Container {
  var widgetState: Factory<WidgetState> {
    Factory(self) { WidgetState() }.scope(.cached)
  }
}

struct WidgetState: Sendable {
  @PersistedThreadSafe("skipForwardInterval", store: Container.shared.sharedDefaults())
  var skipForwardInterval: Int = 30

  @PersistedThreadSafe("skipBackwardInterval", store: Container.shared.sharedDefaults())
  var skipBackwardInterval: Int = 15

  @PersistedThreadSafe("playbackStatus", store: Container.shared.sharedDefaults())
  var playbackStatus: PlaybackStatus = .stopped
}
