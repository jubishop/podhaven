// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import SwiftUI

struct PlayBar: View {
  @State private var viewModel = Container.shared.playBarViewModel()

  var body: some View {
    VStack {
      if let episodeTitle = viewModel.episodeTitle {
        Text(episodeTitle)
          .lineLimit(1)
          .padding(.bottom, 4)
      }
      HStack {
        Group {
          Button(
            action: viewModel.seekBackward,
            label: {
              viewModel.seekBackwardImage.foregroundColor(.white)
            }
          )
          Button(
            action: viewModel.playOrPause,
            label: {
              Image(
                systemName: viewModel.playable
                  ? (viewModel.playing ? "pause.circle" : "play.circle")
                  : "xmark.circle"
              )
              .font(.largeTitle)
              .foregroundColor(.white)
            }
          )
          Button(
            action: viewModel.seekForward,
            label: {
              viewModel.seekForwardImage.foregroundColor(.white)
            }
          )
        }
        .padding(.horizontal)
      }
      Slider(
        value: $viewModel.sliderValue,
        in: 0...Double(viewModel.duration.seconds),
        onEditingChanged: { isEditing in
          viewModel.isDragging = isEditing
        }
      )
      .disabled(!viewModel.playable)
    }
    .padding()
    .background(Color.accentColor)
    .frame(maxWidth: .infinity)
  }
}

#if DEBUG
#Preview {
  PlayBar()
    .preview()
    .task {
      let podcastEpisode = try! await PreviewHelpers.loadPodcastEpisode()
      try? await Container.shared.playManager().load(podcastEpisode)
    }
}
#endif
