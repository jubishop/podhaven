// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import SwiftUI

struct PlayBar: View {
  @InjectedObservable(\.playBarViewModel) private var viewModel

  var body: some View {
    Group {
      if viewModel.isExpanded {
        expandedPlayBar
      } else {
        collapsedPlayBar
      }
    }
    .frame(maxWidth: .infinity)
    .background(Color.accentColor)
  }

  // MARK: - Collapsed PlayBar

  private var collapsedPlayBar: some View {
    HStack(spacing: 12) {
      episodeImage

      Spacer()

      playbackControls

      Spacer()

      Button(action: viewModel.toggleExpansion) {
        Image(systemName: "chevron.up")
          .font(.system(size: 16, weight: .medium))
          .foregroundColor(.white)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
  }

  // MARK: - Expanded PlayBar

  private var expandedPlayBar: some View {
    VStack(spacing: 12) {
      HStack {
        episodeImage

        VStack(alignment: .leading, spacing: 4) {
          if let episodeTitle = viewModel.episodeTitle {
            Text(episodeTitle)
              .font(.headline)
              .foregroundColor(.white)
              .lineLimit(2)
              .multilineTextAlignment(.leading)
          }

          if let podcastTitle = viewModel.podcastTitle {
            Text(podcastTitle)
              .font(.subheadline)
              .foregroundColor(.white.opacity(0.8))
              .lineLimit(1)
          }

          if let publishedAt = viewModel.publishedAt {
            Text(publishedAt, style: .date)
              .font(.caption)
              .foregroundColor(.white.opacity(0.6))
          }
        }

        Spacer()

        Button(action: viewModel.toggleExpansion) {
          Image(systemName: "chevron.down")
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(.white)
        }
      }
      .padding(.horizontal, 16)
      .padding(.top, 12)

      playbackControls
        .padding(.horizontal, 16)

      VStack(spacing: 8) {
        Slider(
          value: $viewModel.sliderValue,
          in: 0...Double(viewModel.duration.seconds),
          onEditingChanged: { isEditing in
            viewModel.isDragging = isEditing
          }
        )
        .tint(.white)

        HStack {
          Text(viewModel.sliderValue.playbackTimeFormat)
            .font(.caption)
            .foregroundColor(.white.opacity(0.8))

          Spacer()

          Text(viewModel.duration.seconds.playbackTimeFormat)
            .font(.caption)
            .foregroundColor(.white.opacity(0.8))
        }
      }
      .padding(.horizontal, 16)
      .padding(.bottom, 16)
    }
  }

  // MARK: - Shared Components

  private var episodeImage: some View {
    Group {
      if let image = viewModel.episodeImage {
        Image(uiImage: image)
          .resizable()
          .aspectRatio(contentMode: .fill)
          .frame(width: 40, height: 40)
          .clipShape(RoundedRectangle(cornerRadius: 8))
      } else {
        RoundedRectangle(cornerRadius: 8)
          .fill(Color.white.opacity(0.2))
          .frame(width: 40, height: 40)
          .overlay(
            Image(systemName: "music.note")
              .foregroundColor(.white.opacity(0.6))
          )
      }
    }
  }

  private var playbackControls: some View {
    HStack(spacing: 20) {
      Button(action: viewModel.seekBackward) {
        viewModel.seekBackwardImage
          .font(.title2)
          .foregroundColor(.white)
      }

      Button(action: viewModel.playOrPause) {
        Image(systemName: viewModel.playing ? "pause.circle.fill" : "play.circle.fill")
          .font(.title)
          .foregroundColor(.white)
      }

      Button(action: viewModel.seekForward) {
        viewModel.seekForwardImage
          .font(.title2)
          .foregroundColor(.white)
      }
    }
  }

}

#if DEBUG
#Preview {
  PlayBar()
    .preview()
    .task {
      let podcastEpisode = try! await PreviewHelpers.loadPodcastEpisode()
      _ = try? await Container.shared.playManager().load(podcastEpisode)
    }
}
#endif
