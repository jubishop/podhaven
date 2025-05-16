// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation
import SwiftUI

@Observable @MainActor final class PlayBarViewModel {
  @ObservationIgnored @DynamicInjected(\.playState) private var playState
  private var playManager: PlayManager { get async { await Container.shared.playManager() } }

  var barWidth: CGFloat = 0
  var isDragging = false

  var episodeTitle: String? { playState.onDeck?.episodeTitle }
  var playable: Bool { playState.playable }
  var playing: Bool { playState.playing }

  private var _sliderValue: Double = 0
  var sliderValue: Double {
    get { isDragging ? _sliderValue : playState.currentTime.seconds }
    set {
      self._sliderValue = newValue
      Task { await playManager.seek(to: CMTime.inSeconds(_sliderValue)) }
    }
  }
  var duration: CMTime { playState.onDeck?.duration ?? CMTime.zero }

  var seekBackwardImage: Image { Image(systemName: "gobackward.15") }
  var seekForwardImage: Image { Image(systemName: "goforward.30") }

  func playOrPause() {
    guard playState.playable else { return }

    if playState.playing {
      Task { await playManager.pause() }
    } else {
      Task { await playManager.play() }
    }
  }

  func seekBackward() {
    Task { await playManager.seekBackward(CMTime.inSeconds(15)) }
  }

  func seekForward() {
    Task { await playManager.seekForward(CMTime.inSeconds(30)) }
  }
}
