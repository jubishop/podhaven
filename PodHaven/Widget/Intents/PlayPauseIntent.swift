// Copyright Justin Bishop, 2026

import AppIntents
import FactoryKit

struct PlayPauseIntent: AudioPlaybackIntent {
  static let title: LocalizedStringResource = "Play or Pause"
  static let description: IntentDescription = "Toggles playback of the current episode."

  func perform() async throws -> some IntentResult {
    #if !WIDGET_EXTENSION
    let appLauncher = Container.shared.appLauncher()
    await appLauncher.prepareForPlayback()

    let sharedState = Container.shared.sharedState()
    let playManager = Container.shared.playManager()

    switch sharedState.playbackStatus {
    case .paused:
      WidgetInfo.playbackStatus = .playing
      await playManager.play()
    case .playing:
      WidgetInfo.playbackStatus = .paused
      await playManager.pause()
    case .stopped, .waiting, .loading:
      break
    }

    return .result()
    #else
    Assert.fatal("PlayPauseIntent should never execute in widget process")
    #endif
  }
}
