// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import SwiftUI

struct PlayBar: View {
  @InjectedObservable(\.playBarViewModel) private var viewModel

  private let imageSize: CGFloat = 48
  private let progressAnimationDuration: Double = 0.15
  private let progressDragScale: Double = 1.1
  private let basicSpacing: CGFloat = 12

  var body: some View {
    Group {
      if viewModel.isLoading {
        loadingPlayBar
      } else if viewModel.isStopped {
        stoppedPlayBar
      } else {
        VStack(spacing: 4) {
          collapsedPlayBar

          if viewModel.isExpanded {
            progressBar
          }
        }
        .padding(.horizontal, 12)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 2)
    .padding(.horizontal, 16)
    .dynamicTypeSize(.xxLarge)
  }

  // MARK: - Loading PlayBar

  private var loadingPlayBar: some View {
    HStack(spacing: basicSpacing) {
      ProgressView()
        .progressViewStyle(CircularProgressViewStyle(tint: .white))
        .scaleEffect(0.8)

      Text("Loading \(viewModel.loadingEpisodeTitle)")
        .foregroundColor(.white)
        .lineLimit(1)

      Spacer()
    }
    .padding(12)
    .glassEffect()
  }

  // MARK: - Stopped PlayBar

  private var stoppedPlayBar: some View {
    HStack(spacing: basicSpacing) {
      AppLabel.noEpisodeSelected.image
        .foregroundColor(.white)

      Text("No episode selected")
        .foregroundColor(.white)

      Spacer()
    }
    .padding(12)
    .glassEffect()
  }

  // MARK: - Collapsed PlayBar

  private var collapsedPlayBar: some View {
    HStack {
      episodeImage

      Spacer()

      playbackControls

      Spacer()

      expansionButton
    }
  }

  // MARK: - Progress Bar

  private var progressBar: some View {
    VStack(spacing: 2) {
      CustomProgressBar(
        value: $viewModel.sliderValue,
        isDragging: $viewModel.isDragging,
        range: 0...Double(viewModel.duration.seconds),
        animationDuration: progressAnimationDuration
      )

      HStack {
        Text(viewModel.sliderValue.playbackTimeFormat)
          .font(.caption2)
          .foregroundColor(.white)
          .scaleEffect(viewModel.isDragging ? progressDragScale : 1.0)
          .animation(
            .easeInOut(duration: progressAnimationDuration),
            value: viewModel.isDragging
          )

        Spacer()

        Text(viewModel.duration.seconds.playbackTimeFormat)
          .font(.caption2)
          .foregroundColor(.white)
          .scaleEffect(viewModel.isDragging ? progressDragScale : 1.0)
          .animation(
            .easeInOut(duration: progressAnimationDuration),
            value: viewModel.isDragging
          )
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 8))
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
    .padding(4)
    .glassEffect(.clear.interactive(), in: .rect(cornerRadius: 8))
  }

  private var playbackControls: some View {
    HStack {
      AppLabel.seekBackward.imageButton {
        viewModel.seekBackward()
      }
      .font(.title2)
      .tint(.white)
      .buttonStyle(.glass)

      playPauseButton
        .font(.title)
        .tint(.white)
        .buttonStyle(.glass)

      AppLabel.seekForward.imageButton {
        viewModel.seekForward()
      }
      .font(.title2)
      .tint(.white)
      .buttonStyle(.glass)
    }
  }

  @ViewBuilder
  private var playPauseButton: some View {
    if viewModel.isWaiting {
      AppLabel.loading.imageButton {
        viewModel.playOrPause()
      }
    } else if viewModel.isPlaying {
      AppLabel.pauseButton.imageButton {
        viewModel.playOrPause()
      }
    } else {
      AppLabel.playButton.imageButton {
        viewModel.playOrPause()
      }
    }
  }

  private var expansionButton: some View {
    Group {
      if viewModel.isExpanded {
        AppLabel.expandDown.imageButton {
          viewModel.toggleExpansion()
        }
      } else {
        AppLabel.expandUp.imageButton {
          viewModel.toggleExpansion()
        }
      }
    }
    .tint(.white)
    .buttonStyle(.glass)
    .contentTransition(.symbolEffect(.replace))
  }
}

// MARK: - Preview

#if DEBUG
  #Preview {
    @Previewable @State var imageURLs: [URL] = []
    @Previewable @State var gridItemSize: CGFloat = 100

    VStack(spacing: 12) {
      HStack(spacing: 24) {
        Button(
          action: { Container.shared.playState().setStatus(.loading("Episode Title Here")) },
          label: {
            ProgressView()
              .progressViewStyle(.circular)
              .tint(.primary)
              .frame(width: 32, height: 32)
          }
        )

        AppLabel.loading.imageButton {
          Container.shared.playState().setStatus(.waiting)
        }

        AppLabel.pauseButton.imageButton {
          Container.shared.playState().setStatus(.playing)
        }

        AppLabel.playButton.imageButton {
          Container.shared.playState().setStatus(.paused)
        }

        AppLabel.noEpisodeSelected.imageButton {
          Container.shared.playState().setStatus(.stopped)
        }
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
