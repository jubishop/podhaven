// Copyright Justin Bishop, 2024

import AVFoundation
import SwiftUI

struct PlayBar: View {
  var body: some View {
    HStack {
      Button(action: {
        // PlayManager.shared.seekBackward()
      }) {
        Image(systemName: "gobackward.10")
      }
      .padding()

      Button(action: {
        guard PlayState.shared.isActive, !PlayState.shared.isLoading else {
          return
        }
        if PlayState.shared.isPlaying {
          Task.detached(priority: .userInitiated) {
            await PlayManager.shared.pause()
          }
        } else {
          Task.detached(priority: .userInitiated) {
            await PlayManager.shared.play()
          }
        }
      }) {
        Image(
          systemName: PlayState.shared.isActive && !PlayState.shared.isLoading
            ? (PlayState.shared.isPlaying
              ? "pause.circle" : "play.circle") : "xmark.circle"
        )
        .font(.largeTitle)
      }
      .padding()

      Button(action: {
        //  PlayManager.shared.seekForward()
      }) {
        Image(systemName: "goforward.10")
      }
      .padding()
    }
  }
}

#Preview {
  PlayBar()
}
