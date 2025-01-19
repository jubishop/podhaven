// Copyright Justin Bishop, 2025

import AVFoundation
import Factory
import SwiftUI

struct PlayBar: View {
  @State private var viewModel = PlayBarViewModel()

  var body: some View {
    VStack {
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
        in: 0...Double(viewModel.duration.seconds),
        onEditingChanged: { isEditing in
          viewModel.isDragging = isEditing
        }
      )
      .disabled(!viewModel.playable)
      .frame(width: viewModel.barWidth)
    }
  }
}

#Preview {
  PlayBar()
    .preview()
    .task {
      let podcastEpisode = try! await PreviewHelpers.loadPodcastEpisode()
      try? await Container.shared.playManager().value.load(podcastEpisode)
    }
}
