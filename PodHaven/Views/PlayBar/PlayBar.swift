// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import SwiftUI

// Eventually we should replace this with TabViewBottomAccessoryPlacement
struct PlayBarAccessory: View {
  nonisolated static let CoordinateName = "TabRoot"

  @State private var isExpanded = true

  private let tabMaxY: CGFloat

  init(tabMaxY: CGFloat) {
    self.tabMaxY = tabMaxY
  }

  var body: some View {
    PlayBar(isExpanded: isExpanded)
      .onGeometryChange(for: CGFloat.self) { proxy in
        proxy.frame(in: .named(Self.CoordinateName)).maxY
      } action: { newMaxY in
        isExpanded = (tabMaxY - newMaxY) > 40
      }
  }
}

struct PlayBar: View {
  @ObservationIgnored @DynamicInjected(\.sheet) private var sheet

  private let basicSpacing: CGFloat = 12

  @State private var viewModel = PlayBarViewModel()

  @State private var playBarSheetIsPresented = false
  private let isExpanded: Bool

  init(isExpanded: Bool) {
    self.isExpanded = isExpanded
  }

  var body: some View {
    Group {
      if viewModel.isLoading {
        loadingPlayBar
      } else if viewModel.isStopped {
        stoppedPlayBar
      } else if isExpanded {
        expandedPlayBar
      } else {
        inlinePlayBar
      }
    }
    .sheet(isPresented: $playBarSheetIsPresented, content: { playBarSheet })
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
    .padding(.horizontal, basicSpacing)
  }

  // MARK: - Stopped PlayBar

  private var stoppedPlayBar: some View {
    HStack(spacing: basicSpacing) {
      AppIcon.noEpisodeSelected.coloredImage

      Text("No episode selected")
        .foregroundColor(.white)

      Spacer()
    }
    .padding(.horizontal, basicSpacing * 2)
  }

  // MARK: - Inline PlayBar

  private var inlinePlayBar: some View {
    HStack {
      playbackControls
    }
    .padding(.horizontal, basicSpacing)
  }

  // MARK: - Expanded PlayBar

  private var expandedPlayBar: some View {
    HStack {
      Button(
        action: viewModel.showEpisodeDetail,
        label: {
          if let image = viewModel.episodeImage {
            Image(uiImage: image)
              .resizable()
              .aspectRatio(contentMode: .fill)
              .clipShape(RoundedRectangle(cornerRadius: 8))
          } else {
            RoundedRectangle(cornerRadius: 8)
              .aspectRatio(contentMode: .fill)
              .overlay(AppIcon.audioPlaceholder.coloredImage)
          }
        }
      )

      Spacer()

      playbackControls

      Spacer()

      AppIcon.expandUp.imageButton {
        playBarSheetIsPresented = true
      }
    }
    .padding(.horizontal, basicSpacing * 2)
  }

  // MARK: - PlayBar Sheet

  private var playBarSheet: some View {
    ZStack {
      Group {
        if let image = viewModel.episodeImage {
          Color.black
            .overlay(alignment: .center) {
              Image(uiImage: image)
                .resizable()
                .scaledToFill()
            }
        } else {
          Color.black
            .overlay(alignment: .top) {
              AppIcon.audioPlaceholder.coloredImage
                .font(.system(size: basicSpacing * 12))
                .padding(.top, basicSpacing * 4)
            }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .clipped()
      .ignoresSafeArea()

      VStack(spacing: basicSpacing) {
        Spacer()

        HStack {
          Spacer()
          Spacer()

          AppIcon.seekBackward.imageButton(action: viewModel.seekBackward)
            .font(.title2)
            .buttonStyle(.glass)

          Spacer()

          playPauseButton
            .font(.title)
            .buttonStyle(.glass)

          Spacer()

          AppIcon.seekForward.imageButton(action: viewModel.seekForward)
            .font(.title2)
            .buttonStyle(.glass)

          Spacer()
          Spacer()
        }

        progressBar
          .padding(.horizontal, basicSpacing)
      }
      .padding(.horizontal, basicSpacing)
    }
    .presentationDetents([.medium])
  }

  @ViewBuilder
  private var progressBar: some View {
    let progressAnimationDuration: Double = 0.15
    let progressDragScale: Double = 1.1

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
    .padding(12)
    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 8))
  }

  // MARK: - Shared Components

  @ViewBuilder
  private var playbackControls: some View {
    Spacer()

    AppIcon.seekBackward.imageButton(action: viewModel.seekBackward)

    Spacer()

    playPauseButton
      .font(.title3)

    Spacer()

    AppIcon.seekForward.imageButton(action: viewModel.seekForward)

    Spacer()
  }

  @ViewBuilder
  private var playPauseButton: some View {
    let action = viewModel.playOrPause
    if viewModel.isWaiting {
      AppIcon.loading.imageButton(action: action)
    } else if viewModel.isPlaying {
      AppIcon.pauseButton.imageButton(action: action)
    } else {
      AppIcon.playButton.imageButton(action: action)
    }
  }
}

// MARK: - Preview

#if DEBUG
struct PlayBarPreview: View {
  var playState: PlayState { Container.shared.playState() }

  let image: UIImage?

  init(
    _ status: PlaybackStatus,
    image: UIImage? = PreviewBundle.loadImage(
      named: "pod-save-america-podcast",
      in: .EpisodeThumbnails
    )
  ) {
    self.image = image
    playState.setStatus(status)
  }

  var body: some View {
    ContentView()
      .preview()
      .task {
        playState.setOnDeck(
          OnDeck(
            episodeID: Episode.ID(1),
            feedURL: FeedURL(URL.valid()),
            guid: GUID(String.random()),
            podcastTitle: "Podcast Title",
            podcastURL: URL.valid(),
            episodeTitle: "Episode Title",
            duration: CMTime.minutes(60),
            image: image,
            mediaURL: MediaURL(URL.valid()),
            pubDate: 48.hoursAgo
          )
        )
        playState.setCurrentTime(CMTime.minutes(30))

        for _ in 1...10 {
          _ = try! await Create.podcastEpisode()
        }
        Container.shared.navigation().showPodcastList(.unsubscribed)
      }
  }
}

#Preview("waiting") {
  PlayBarPreview(.waiting)
}

#Preview("playing") {
  PlayBarPreview(.playing)
}

#Preview("no image") {
  PlayBarPreview(.playing, image: nil)
}

#Preview("paused") {
  PlayBarPreview(.paused)
}

#Preview("stopped") {
  PlayBarPreview(.stopped)
}

#Preview("loading") {
  PlayBarPreview(.loading("Episode Title Here"))
}

#endif
