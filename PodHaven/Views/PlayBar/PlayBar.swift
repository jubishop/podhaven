// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import SwiftUI

struct PlayBar: View {
  @InjectedObservable(\.playBarViewModel) private var viewModel

  private let imageSize: CGFloat = 40

  var body: some View {
    Group {
      if viewModel.isLoading {
        loadingPlayBar
      } else if viewModel.isStopped {
        stoppedPlayBar
      } else if viewModel.isExpanded {
        expandedPlayBar
      } else {
        collapsedPlayBar
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .frame(maxWidth: .infinity)
    .background(Color.accentColor)
  }

  // MARK: - Loading PlayBar

  private var loadingPlayBar: some View {
    HStack(spacing: viewModel.commonSpacing) {
      ProgressView()
        .progressViewStyle(CircularProgressViewStyle(tint: .white))
        .scaleEffect(0.8)

      Text("Loading \(viewModel.loadingEpisodeTitle)")
        .foregroundColor(.white)
        .lineLimit(1)

      Spacer()
    }
  }

  // MARK: - Stopped PlayBar

  private var stoppedPlayBar: some View {
    HStack(spacing: viewModel.commonSpacing) {
      AppLabel.noEpisodeSelected.image
        .foregroundColor(.white)

      Text("No episode selected")
        .foregroundColor(.white)

      Spacer()
    }
  }

  // MARK: - Collapsed PlayBar

  private var collapsedPlayBar: some View {
    HStack(spacing: viewModel.commonSpacing) {
      episodeImage

      Spacer()

      playbackControls

      Spacer()

      expansionButton
    }
  }

  // MARK: - Expanded PlayBar

  private var expandedPlayBar: some View {
    VStack(spacing: 16) {
      collapsedPlayBar

      VStack(spacing: 4) {
        CustomProgressBar(
          value: $viewModel.sliderValue,
          isDragging: $viewModel.isDragging,
          range: 0...Double(viewModel.duration.seconds),
          animationDuration: viewModel.progressAnimationDuration
        )

        HStack {
          Text(viewModel.sliderValue.playbackTimeFormat)
            .font(.caption)
            .foregroundColor(.white)
            .scaleEffect(viewModel.isDragging ? viewModel.progressDragScale : 1.0)
            .animation(
              .easeInOut(duration: viewModel.progressAnimationDuration),
              value: viewModel.isDragging
            )

          Spacer()

          Text(viewModel.duration.seconds.playbackTimeFormat)
            .font(.caption)
            .foregroundColor(.white)
            .scaleEffect(viewModel.isDragging ? viewModel.progressDragScale : 1.0)
            .animation(
              .easeInOut(duration: viewModel.progressAnimationDuration),
              value: viewModel.isDragging
            )
        }
      }
    }
  }

  // MARK: - Shared Components

  private var episodeImage: some View {
    Button(
      action: viewModel.showEpisodeDetail,
      label: {
        Group {
          if let image = viewModel.episodeImage {
            Image(uiImage: image)
              .resizable()
              .aspectRatio(contentMode: .fill)
              .frame(width: imageSize, height: imageSize)
              .clipShape(RoundedRectangle(cornerRadius: 8))
          } else {
            RoundedRectangle(cornerRadius: 8)
              .fill(Color.white.opacity(0.2))
              .frame(width: imageSize, height: imageSize)
              .overlay(
                AppLabel.audioPlaceholder.image
                  .foregroundColor(.white.opacity(0.6))
              )
          }
        }
      }
    )
  }

  private var playbackControls: some View {
    HStack(spacing: 32) {
      Button(action: viewModel.seekBackward) {
        viewModel.seekBackwardImage
          .font(.title2)
          .foregroundColor(.white)
      }

      Button(action: viewModel.playOrPause) {
        Group {
          if viewModel.isWaiting {
            AppLabel.loading.image
              .font(.title)
              .foregroundColor(.white)
          } else if viewModel.isPlaying {
            AppLabel.pauseButton.image
              .font(.title)
              .foregroundColor(.white)
          } else {
            AppLabel.playButton.image
              .font(.title)
              .foregroundColor(.white)
          }
        }
      }

      Button(action: viewModel.seekForward) {
        viewModel.seekForwardImage
          .font(.title2)
          .foregroundColor(.white)
      }
    }
  }

  private var expansionButton: some View {
    Button(action: viewModel.toggleExpansion) {
      (viewModel.isExpanded ? AppLabel.expandDown.image : AppLabel.expandUp.image)
        .foregroundColor(.white)
    }
  }
}

// MARK: - Preview

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
