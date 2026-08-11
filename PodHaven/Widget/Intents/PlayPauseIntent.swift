// Copyright Justin Bishop, 2026

import AppIntents
import FactoryKit
import Logging

struct PlayPauseIntent: SetValueIntent, AudioPlaybackIntent {
  static let title: LocalizedStringResource = "Play or Pause"
  static let description: IntentDescription = "Toggles playback of the current episode."
  private static let log = Log.as("PlayPauseIntent")

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
    let sharedState = Container.shared.sharedState()
    let widgetState = Container.shared.widgetState()
    let applicationState = await Container.shared.uiApplication().applicationState
    Self.log.info(
      """
      event=playPauseIntent requestedPlaying=\(value) appState=\(applicationState) \
      currentEpisodeID=\(String(describing: sharedState.currentEpisodeID)) \
      onDeckEpisodeID=\(String(describing: sharedState.onDeck?.id)) \
      playbackStatus=\(sharedState.playbackStatus)
      """
    )
    if value {
      widgetState.playbackStatus = .playing
      await playManager.play(origin: .widget)
      if sharedState.onDeck == nil {
        widgetState.playbackStatus = sharedState.playbackStatus
      }
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
