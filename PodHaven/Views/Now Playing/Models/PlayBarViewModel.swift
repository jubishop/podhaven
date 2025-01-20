// Copyright Justin Bishop, 2025

import AVFoundation
import Factory
import Foundation
import SwiftUI

@Observable @MainActor final class PlayBarViewModel {
  @ObservationIgnored @LazyInjected(\.playManager) private var playManager

  var barWidth: CGFloat = 0
  var isDragging = false

  var episodeTitle: String? { PlayState.onDeck?.episodeTitle }
  var playable: Bool { PlayState.playable }
  var playing: Bool { PlayState.playing }

  private var _sliderValue: Double = 0
  var sliderValue: Double {
    get { isDragging ? _sliderValue : PlayState.currentTime.seconds }
    set {
      self._sliderValue = newValue
      Task { await playManager.seek(to: CMTime.inSeconds(_sliderValue)) }
    }
  }
  var duration: CMTime { PlayState.onDeck?.duration ?? CMTime.zero }

  var seekBackwardImage: Image {
    Image(systemName: "gobackward.15")
  }
  var seekForwardImage: Image {
    Image(systemName: "goforward.30")
  }

  func playOrPause() {
    guard PlayState.playable else { return }

    if PlayState.playing {
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
