// Copyright Justin Bishop, 2024

import AVFoundation
import Foundation
import SwiftUI

@Observable @MainActor final class PlayBarViewModel {
  var barWidth: CGFloat = 0
  var isDragging = false

  var playable: Bool { PlayState.playable }
  var playing: Bool { PlayState.playing }

  private var _sliderValue: Double = 0
  var sliderValue: Double {
    get { isDragging ? _sliderValue : PlayState.currentTime.seconds }
    set {
      self._sliderValue = newValue
      Task { @PlayActor in
        await PlayManager.shared.seek(to: CMTime.inSeconds(_sliderValue))
      }
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
      Task { @PlayActor in PlayManager.shared.pause() }
    } else {
      Task { @PlayActor in PlayManager.shared.play() }
    }
  }

  func seekBackward() {
    Task { @PlayActor in
      PlayManager.shared.seekBackward(CMTime.inSeconds(15))
    }
  }

  func seekForward() {
    Task { @PlayActor in
      PlayManager.shared.seekForward(CMTime.inSeconds(30))
    }
  }
}
