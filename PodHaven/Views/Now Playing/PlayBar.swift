// Copyright Justin Bishop, 2024

import AVFoundation
import SwiftUI

struct PlayBar: View {
  var body: some View {
    HStack {
      Group {
        Button(action: {
          Task.detached(priority: .userInitiated) {
            await PlayManager.shared.seekForward()
          }
        }) {
          Image(systemName: "gobackward.10").foregroundColor(.white)
        }
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
          .foregroundColor(.white)
        }
        Button(action: {
          Task.detached(priority: .userInitiated) {
            await PlayManager.shared.seekForward()
          }
        }) {
          Image(systemName: "goforward.10").foregroundColor(.white)
        }
      }
      .padding(.horizontal)
    }
    .padding()
    .background(Color.blue)
    .cornerRadius(16)
  }
}

#Preview {
  struct PlayBarPreview: View {
    init() {
      Task {
        try await PlayManager.shared.load(
          URL(
            string:
              "https://pdst.fm/e/chrt.fm/track/479722/arttrk.com/p/CRMDA/claritaspod.com/measure/pscrb.fm/rss/p/mgln.ai/e/284/pdrl.fm/b85a46/stitcher.simplecastaudio.com/9aa1e238-cbed-4305-9808-c9228fc6dd4f/episodes/97cb195d-ed09-4644-bd9d-215623b0a9bf/audio/128/default.mp3?aid=rss_feed&amp;awCollectionId=9aa1e238-cbed-4305-9808-c9228fc6dd4f&amp;awEpisodeId=97cb195d-ed09-4644-bd9d-215623b0a9bf&amp;feed=dxZsm5kX"
          )!
        )
      }
    }
    var body: some View {
      PlayBar()
    }
  }
  return Preview { PlayBarPreview() }
}
