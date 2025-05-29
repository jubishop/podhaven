// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation
import SwiftUI

extension Container {
  @MainActor var playBarViewModel: Factory<PlayBarViewModel> {
    Factory(self) { @MainActor in PlayBarViewModel() }.scope(.cached)
  }
}

@Observable @MainActor class PlayBarViewModel {
  @ObservationIgnored @DynamicInjected(\.playManager) private var playManager
  @ObservationIgnored @DynamicInjected(\.playState) private var playState

  // MARK: - State Management

  var episodeTitle: String? { playState.onDeck?.episodeTitle }
  var playable: Bool { playState.playable }
  var playing: Bool { playState.playing }

  var isDragging = false
  private var _sliderValue: Double = 0
  var sliderValue: Double {
    get { isDragging ? _sliderValue : playState.currentTime.seconds }
    set {
      self._sliderValue = newValue
      Task { [weak self] in
        guard let self else { return }
        await playManager.seek(to: CMTime.inSeconds(_sliderValue))
      }
    }
  }
  var duration: CMTime { playState.onDeck?.duration ?? CMTime.zero }

  var seekBackwardImage: Image { Image(systemName: "gobackward.15") }
  var seekForwardImage: Image { Image(systemName: "goforward.30") }

  func playOrPause() {
    guard playState.playable else { return }

    if playState.playing {
      Task { [weak self] in
        guard let self else { return }
        await playManager.pause()
      }
    } else {
      Task { [weak self] in
        guard let self else { return }
        await playManager.play()
      }
    }
  }

  func seekBackward() {
    Task { [weak self] in
      guard let self else { return }
      await playManager.seekBackward(CMTime.inSeconds(15))
    }
  }

  func seekForward() {
    Task { [weak self] in
      guard let self else { return }
      await playManager.seekForward(CMTime.inSeconds(30))
    }
  }
}
