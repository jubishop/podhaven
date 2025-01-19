// Copyright Justin Bishop, 2025

import AVFoundation
import Factory
import SwiftUI

struct PlayBar: View {
  @State private var viewModel = PlayBarViewModel()

  var body: some View {
    VStack {
      if let episodeTitle = viewModel.episodeTitle {
        Text(episodeTitle)
          .lineLimit(1)
          .padding(.bottom)
          .frame(width: viewModel.barWidth)
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
      .onGeometryChange(for: CGFloat.self) { geometry in
        geometry.size.width
      } action: { newWidth in
        viewModel.barWidth = newWidth
      }
      Slider(
        value: $viewModel.sliderValue,
        in: 0...Double(viewModel.duration.seconds),
        onEditingChanged: { isEditing in
          viewModel.isDragging = isEditing
        }
      )
      .disabled(!viewModel.playable)
      .frame(width: viewModel.barWidth)
    }
    .padding()
    .background(Color.blue)
    .cornerRadius(16)
  }
}

#Preview {
  PlayBar()
    .preview()
    .task {
      let podcastEpisode = try! await PreviewHelpers.loadPodcastEpisode()
      try? await Container.shared.playManager().load(podcastEpisode)
    }
}
