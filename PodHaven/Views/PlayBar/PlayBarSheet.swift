// Copyright Justin Bishop, 2025

import CoreMedia
import FactoryKit
import SwiftUI

struct PlayBarSheet: View {
  @DynamicInjected(\.sharedState) private var sharedState

  private let spacing: CGFloat = 12

  @Bindable var viewModel: PlayBarViewModel
  @Environment(\.colorScheme) private var colorScheme
  @State private var containerWidth: CGFloat = 1
  @State private var isShowingSpeedPopover = false

  init(viewModel: PlayBarViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    ZStack {
      sheetArtwork

      VStack(spacing: spacing) {
        HStack(spacing: spacing) {
          if sharedState.onDeck != nil {
            topBarButtonStyle(stopAfterEpisodeButton)
          }

          Spacer()

          if let onDeck = sharedState.onDeck {
            topBarButtonStyle(ShareEpisodeButton(episode: onDeck))
            topBarButtonStyle(ratingMenu(rating: onDeck.rating))
          }
        }
        .padding(.horizontal, spacing)
        .padding(.top, spacing)

        Spacer()

        HStack {
          playbackMetaControls
        }
        .padding(.horizontal, spacing)

        HStack {
          Spacer()

          playbackControls

          Spacer()
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.undoSeekDirection)

        progressBar
          .padding(.horizontal, spacing)
      }
      .padding(.horizontal, spacing)
      .onGeometryChange(for: CGFloat.self) { proxy in
        proxy.size.width
      } action: { newWidth in
        containerWidth = newWidth
      }
    }
    .presentationDetents([.medium])
  }

  @ViewBuilder
  private var sheetArtwork: some View {
    GeometryReader { geometry in
      if let image = viewModel.episodeImage {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
          .frame(width: geometry.size.width, height: geometry.size.height)
          .clipped()
          .overlay((colorScheme == .dark ? Color.black : Color.white).opacity(0.5))
      } else {
        (colorScheme == .dark ? Color.black : Color.white)
          .overlay(alignment: .top) {
            AppIcon.audioPlaceholder.image
              .font(.system(size: spacing * 12))
              .padding(.top, spacing * 4)
          }
      }
    }
    .ignoresSafeArea()
  }

  private var stopAfterEpisodeButton: some View {
    let icon: AppIcon =
      sharedState.stopAfterCurrentEpisode ? .stopAfterEpisodeOn : .stopAfterEpisode
    return icon.imageButton { viewModel.toggleStopAfterCurrentEpisode() }
  }

  @ViewBuilder
  private func ratingMenu(rating: EpisodeRating?) -> some View {
    Menu {
      ratingMenuButtons(showClear: rating != nil, rate: viewModel.rate)
    } label: {
      AppIcon.rating(for: rating).image
    }
  }

  private func topBarButtonStyle<V: View>(_ content: V) -> some View {
    content
      .font(.title3)
      .padding(spacing / 2)
      .glassEffect(.clear.interactive(), in: .capsule)
      .disabled(isShowingSpeedPopover)
  }

  private func metaButtonStyle<V: View>(_ content: V) -> some View {
    content
      .font(.callout)
      .fontWeight(.semibold)
      .fontDesign(.rounded)
      .padding(.horizontal, spacing)
      .padding(.vertical, spacing / 2)
      .glassEffect(.clear.interactive(), in: .capsule)
  }

  @ViewBuilder
  private var finishOrJumpButton: some View {
    if viewModel.canJumpToMaxPlayback {
      AppIcon.jumpToMaxPosition.imageButton { viewModel.jumpToMaxPlayback() }
    } else {
      AppIcon.finishEpisode.imageButton { viewModel.finishEpisode() }
    }
  }

  @ViewBuilder
  private var playbackMetaControls: some View {
    ZStack {
      HStack {
        metaButtonStyle(
          PlaybackSpeedButton(
            rate: viewModel.playbackRate,
            isShowingPopover: $isShowingSpeedPopover,
            containerWidth: containerWidth
          )
        )

        Spacer()

        metaButtonStyle(finishOrJumpButton)
          .disabled(isShowingSpeedPopover)
      }

      if viewModel.hasChapters {
        HStack(spacing: spacing * 3) {
          metaButtonStyle(
            AppIcon.previousChapter
              .imageButton {
                viewModel.goToPreviousChapter()
              }
          )
          .disabled(isShowingSpeedPopover)

          metaButtonStyle(
            AppIcon.nextChapter
              .imageButton {
                viewModel.goToNextChapter()
              }
          )
          .disabled(isShowingSpeedPopover || !viewModel.canGoToNextChapter)
        }
      }
    }
  }

  private func playbackButtonStyle<V: View>(_ content: V, font: Font = .title2) -> some View {
    content
      .font(font)
      .padding(spacing / 2)
      .glassEffect(.clear.interactive(), in: .capsule)
      .disabled(isShowingSpeedPopover)
      .transition(.scale.combined(with: .opacity))
  }

  @ViewBuilder
  private var playbackControls: some View {
    Spacer()

    if viewModel.undoSeekDirection == .backward {
      playbackButtonStyle(AppIcon.undoSeekBackward.imageButton(action: viewModel.undoSeek))
    } else {
      playbackButtonStyle(SeekBackwardButton(action: viewModel.seekBackward))
    }

    Spacer()

    playbackButtonStyle(PlayPauseButton(action: viewModel.playOrPause), font: .title)

    Spacer()

    if viewModel.undoSeekDirection == .forward {
      playbackButtonStyle(AppIcon.undoSeekForward.imageButton(action: viewModel.undoSeek))
    } else {
      playbackButtonStyle(SeekForwardButton(action: viewModel.seekForward))
    }

    Spacer()
  }

  @ViewBuilder
  private var progressBar: some View {
    let progressAnimationDuration: Double = 0.15
    let progressDragScale: Double = 1.1

    VStack(spacing: 2) {
      ProgressBar(
        value: $viewModel.sliderValue,
        isDragging: $viewModel.isDragging,
        range: 0...viewModel.duration.seconds,
        animationDuration: progressAnimationDuration,
        tickMarks: viewModel.chapterPositions,
        maxPlaybackTime: viewModel.canJumpToMaxPlayback ? viewModel.maxPlaybackTime : nil
      )

      HStack {
        Text(viewModel.sliderValue.playbackTimeFormat)
          .font(.caption2)
          .foregroundColor(.primary)
          .scaleEffect(viewModel.isDragging ? progressDragScale : 1.0)
          .animation(
            .easeInOut(duration: progressAnimationDuration),
            value: viewModel.isDragging
          )

        Spacer()

        Text((viewModel.sliderValue - viewModel.duration.seconds).playbackTimeFormat)
          .font(.caption2)
          .foregroundColor(.primary)
          .scaleEffect(viewModel.isDragging ? progressDragScale : 1.0)
          .animation(
            .easeInOut(duration: progressAnimationDuration),
            value: viewModel.isDragging
          )
      }
    }
    .padding(spacing)
    .glassEffect(.clear.interactive(), in: .rect(cornerRadius: viewModel.isDragging ? 12 : 8))
  }
}

// MARK: - Previews

#if DEBUG
struct PlayBarSheetPreview: View {
  private var sharedState: SharedState { Container.shared.sharedState() }

  let status: PlaybackStatus
  let image: UIImage?
  let currentTimeSeconds: Double
  let maxPlaybackTimeSeconds: Double
  let durationSeconds: Double
  let description: String?

  init(
    _ status: PlaybackStatus = .playing,
    image: UIImage? = PreviewBundle.loadImage(
      named: "pod-save-america-podcast",
      in: .EpisodeThumbnails
    ),
    currentTime: Double = 120,
    maxPlaybackTime: Double = 120,
    duration: Double = 2400,
    description: String? = nil
  ) {
    self.status = status
    self.image = image
    self.currentTimeSeconds = currentTime
    self.maxPlaybackTimeSeconds = maxPlaybackTime
    self.durationSeconds = duration
    self.description = description
  }

  var body: some View {
    PlayBarSheet(viewModel: PlayBarViewModel())
      .preview()
      .task {
        sharedState.setPlaybackStatus(status)

        let unsavedEpisode = try! Create.unsavedEpisode(
          duration: CMTime.seconds(durationSeconds),
          description: description
        )
        let podcastEpisode = try! await Create.podcastEpisode(unsavedEpisode)
        var onDeck = OnDeck(from: podcastEpisode)
        onDeck.artwork = image
        onDeck.currentTime = CMTime.seconds(currentTimeSeconds)
        onDeck.maxPlaybackTime = CMTime.seconds(maxPlaybackTimeSeconds)
        sharedState.$onDeck.new(onDeck)
      }
  }
}

#Preview("at peak — finish button") {
  PlayBarSheetPreview(currentTime: 600, maxPlaybackTime: 600)
}

#Preview("peak ahead — jump button + marker") {
  PlayBarSheetPreview(currentTime: 400, maxPlaybackTime: 1400)
}

#Preview("with chapters") {
  PlayBarSheetPreview(
    currentTime: 300,
    maxPlaybackTime: 300,
    description: """
      Intro 00:00 — Guest 05:30 — Deep dive 18:00 — Break 25:15 — Closing 32:00
      """
  )
}

#Preview("chapters + peak ahead") {
  PlayBarSheetPreview(
    currentTime: 120,
    maxPlaybackTime: 1500,
    description: """
      Intro 00:00 — Guest 05:30 — Deep dive 18:00 — Break 25:15 — Closing 32:00
      """
  )
}

#Preview("no artwork") {
  PlayBarSheetPreview(image: nil)
}

#Preview("loading") {
  PlayBarSheetPreview(
    .loading("Fetching episode…"),
    currentTime: 0,
    maxPlaybackTime: 0
  )
}
#endif
