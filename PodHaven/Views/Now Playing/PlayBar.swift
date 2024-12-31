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
              PlayManager.shared.seekBackward(CMTime.inSeconds(15))
            }
          }) {
            Image(systemName: "gobackward.15").foregroundColor(.white)
          }
          Button(action: {
            guard PlayState.playable else { return }

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
              PlayManager.shared.seekForward(CMTime.inSeconds(30))
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
        in: 0...Double(PlayState.onDeck?.duration.seconds ?? 0),
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
  Preview {
    PlayBar()
  }
  .task {
    let podcastEpisode = try! await Helpers.loadPodcastEpisode()
    await PlayManager.shared.load(podcastEpisode)
  }
}
