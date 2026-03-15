// Copyright Justin Bishop, 2026

import AppIntents
import FactoryKit

struct PlayPauseIntent: SetValueIntent, AudioPlaybackIntent {
  static let title: LocalizedStringResource = "Play or Pause"
  static let description: IntentDescription = "Toggles playback of the current episode."

  @Parameter(title: "Playing")
  var value: Bool

  // Convenience for widget buttons that know the desired next state.
  init(playing: Bool) {
    value = playing
  }

  init() {}

  func perform() async throws -> some IntentResult {
    #if !WIDGET_EXTENSION
    let appLauncher = Container.shared.appLauncher()
    await appLauncher.prepareForPlayback()

    let playManager = Container.shared.playManager()
    let widgetState = Container.shared.widgetState()
    if value {
      widgetState.playbackStatus = .playing
      await playManager.play()
    } else {
      widgetState.playbackStatus = .paused
      await playManager.pause()
    }

    return .result()
    #else
    Assert.fatal("PlayPauseIntent should never execute in widget process")
    #endif
  }
}
