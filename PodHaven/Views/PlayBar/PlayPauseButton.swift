// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

struct PlayPauseButton: View {
  @InjectedObservable(\.playState) private var playState

  let action: @MainActor () -> Void

  var body: some View {
    if playState.waiting {
      AppIcon.loading.imageButton(action: action)
    } else if playState.playing {
      AppIcon.pauseButton.imageButton(action: action)
    } else {
      AppIcon.playButton.imageButton(action: action)
    }
  }
}
