// Copyright Justin Bishop, 2024

import Foundation
import SwiftUI

@Observable @MainActor final class PlayBarViewModel {
  var barWidth: CGFloat = 0
  var isDragging: Bool = false

  private var _sliderValue: Double = 0
  var sliderValue: Double {
    get {
      self.isDragging
        ? self._sliderValue : PlayState.shared.currentTime.seconds
    }
    set {
      self._sliderValue = newValue
      Task(priority: .userInitiated) { @PlayManager in
        await PlayManager.shared.seek(
          to: PlayManager.CMTime(seconds: self._sliderValue)
        )
      }
    }
  }

  init() {}
}
