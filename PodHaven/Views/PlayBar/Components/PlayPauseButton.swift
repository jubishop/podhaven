// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

struct PlayPauseButton: View {
  @DynamicInjected(\.sharedState) private var sharedState

  let action: @MainActor () -> Void

  var body: some View {
    if sharedState.playbackStatus.waiting {
      AppIcon.loading.imageButton(action: action)
    } else if sharedState.playbackStatus.playing {
      AppIcon.pauseButton.imageButton(action: action)
    } else {
      AppIcon.playButton.imageButton(action: action)
    }
  }
}
