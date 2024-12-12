// Copyright Justin Bishop, 2024

import AVFoundation
import SwiftUI

struct PlayBar: View {
  @State private var buttonWidth: CGFloat = 0

  var body: some View {
    VStack {
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
      .onGeometryChange(for: CGFloat.self) { geometry in
        geometry.size.width
      } action: { newWidth in
        buttonWidth = newWidth
      }
      Slider(
        value: .constant(PlayState.shared.currentTime.seconds),
        in: 0...PlayState.shared.duration.seconds
      ).disabled(true).frame(width: buttonWidth)
    }
  }
}

#Preview {
  struct PlayBarPreview: View {
    init() {
      Task {
        let podcastEpisode = try! await PodcastRepository.shared.db.read { db in
          try! Episode
            .including(required: Episode.podcast)
            .shuffled()
            .asRequest(of: PodcastEpisode.self)
            .fetchOne(db)!
        }
        try await PlayManager.shared.load(podcastEpisode)
      }
    }
    var body: some View {
      PlayBar()
    }
  }
  return Preview { PlayBarPreview() }
}
