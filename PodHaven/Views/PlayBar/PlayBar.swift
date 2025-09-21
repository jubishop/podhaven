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
    .padding(.horizontal, 16)
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
  @Previewable @State var imageURLs: [URL] = []
  @Previewable @State var gridItemSize: CGFloat = 100

  VStack(spacing: 12) {
    HStack(spacing: 24) {
      Button {
        Container.shared.playState().setStatus(.loading("Episode Title Here"))
      } label: {
        ProgressView()
          .progressViewStyle(.circular)
          .tint(.primary)
          .frame(width: 32, height: 32)
      }

      Button {
        Container.shared.playState().setStatus(.waiting)
      } label: { AppLabel.loading.image }

      Button {
        Container.shared.playState().setStatus(.playing)
      } label: { AppLabel.pauseButton.image }

      Button {
        Container.shared.playState().setStatus(.paused)
      } label: { AppLabel.playButton.image }

      Button {
        Container.shared.playState().setStatus(.stopped)
      } label: { AppLabel.noEpisodeSelected.image }
    }
    .font(.title)
    .buttonStyle(.plain)
    .dynamicTypeSize(.large)

    ZStack(alignment: .bottom) {
      List(imageURLs, id: \.self) { url in
        SquareImage(image: url, size: $gridItemSize)
      }

      PlayBar()
        .padding(.bottom, 40)
    }
  }
  .preview()
  .task {
    let allThumbnails = PreviewBundle.loadAllThumbnails()
    for thumbnailInfo in allThumbnails.values {
      imageURLs.append(thumbnailInfo.url)
    }

    let playState = Container.shared.playState()
    playState.setOnDeck(
      OnDeck(
        episodeID: Episode.ID(1),
        feedURL: FeedURL(URL.valid()),
        guid: GUID(String.random()),
        podcastTitle: "Podcast Title",
        podcastURL: URL.valid(),
        episodeTitle: "Episode Title",
        duration: CMTime.minutes(60),
        image: allThumbnails.randomElement()!.value.image,
        mediaURL: MediaURL(URL.valid()),
        pubDate: 48.hoursAgo
      )
    )
    playState.setStatus(.playing)
    playState.setCurrentTime(CMTime.minutes(30))
  }
}
#endif
