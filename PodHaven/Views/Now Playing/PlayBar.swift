// Copyright Justin Bishop, 2024

import AVFoundation
import SwiftUI

struct PlayBar: View {
  @State private var viewModel = PlayBarViewModel()

  var body: some View {
    VStack {
      HStack {
        Group {
          Button(action: {
            Task { @PlayActor in
              PlayManager.shared.seekBackward(PlayManager.CMTimeInSeconds(15))
            }
          }) {
            Image(systemName: "gobackward.15").foregroundColor(.white)
          }
          Button(action: {
            guard PlayState.playable
            else { return }
            if PlayState.playing {
              Task { @PlayActor in PlayManager.shared.pause() }
            } else {
              Task { @PlayActor in PlayManager.shared.play() }
            }
          }) {
            Image(
              systemName: PlayState.playable
                ? (PlayState.playing
                  ? "pause.circle" : "play.circle") : "xmark.circle"
            )
            .font(.largeTitle)
            .foregroundColor(.white)
          }
          Button(action: {
            Task { @PlayActor in
              PlayManager.shared.seekForward(PlayManager.CMTimeInSeconds(30))
            }
          }) {
            Image(systemName: "goforward.30").foregroundColor(.white)
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
        viewModel.barWidth = newWidth
      }
      Slider(
        value: $viewModel.sliderValue,
        in: 0...PlayState.duration.seconds,
        onEditingChanged: { isEditing in
          viewModel.isDragging = isEditing
        }
      )
      .disabled(!PlayState.playable)
      .frame(width: viewModel.barWidth)
    }
  }
}

#Preview {
  struct PlayBarPreview: View {
    init() {
      Task {
        let podcastEpisode = try! await Repo.shared.db.read { db in
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
      Text(PlayState.onDeck?.podcast.title ?? "")
      Text(PlayState.onDeck?.episode.title ?? "")
      PlayBar()
    }
  }
  return Preview { PlayBarPreview() }
}
