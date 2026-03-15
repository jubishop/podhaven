// Copyright Justin Bishop, 2026

import FactoryKit
import Logging
import SwiftUI
import WidgetKit

struct PlayPauseValueProvider: ControlValueProvider {
  private static let log = Log.as(LogSubsystem.Widget.controlCenter)

  var previewValue: Bool { false }

  func currentValue() async throws -> Bool {
    let state = Container.shared.widgetState()
    state.$playbackStatus.refresh()
    let isPlaying = state.playbackStatus.playing
    Self.log.debug(
      "PlayPauseValueProvider.currentValue: status=\(state.playbackStatus), isPlaying=\(isPlaying)"
    )
    return isPlaying
  }
}

struct PlayPauseControl: ControlWidget {
  var body: some ControlWidgetConfiguration {
    StaticControlConfiguration(
      kind: WidgetInfo.playPauseControlKind,
      provider: PlayPauseValueProvider()
    ) { isPlaying in
      ControlWidgetToggle(isOn: isPlaying, action: PlayPauseIntent()) {
        if isPlaying {
          AppIcon.pauseButton.rawLabel
        } else {
          AppIcon.playButton.rawLabel
        }
      }
    }
    .displayName("Play / Pause")
    .description("Toggle playback of the current episode.")
  }
}
