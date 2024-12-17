// Copyright Justin Bishop, 2024

import Foundation
import SwiftUI

@Observable @MainActor final class PlayBarViewModel {
  var barWidth: CGFloat = 0
  var isDragging = false

  private var _sliderValue: Double = 0
  var sliderValue: Double {
    get { isDragging ? _sliderValue : PlayState.currentTime.seconds }
    set {
      self._sliderValue = newValue
      Task { @PlayActor in
        await PlayManager.shared.seek(
          to: PlayManager.CMTime(seconds: _sliderValue)
        )
      }
    }
  }

  init() {}
}
