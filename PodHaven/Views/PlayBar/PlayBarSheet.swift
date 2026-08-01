// Copyright Justin Bishop, 2025

import CoreMedia
import FactoryKit
import SwiftUI

struct PlayBarSheet: View {
  @DynamicInjected(\.sharedState) private var sharedState

  private let spacing: CGFloat = 12

  @Bindable var viewModel: PlayBarViewModel
  @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
  @Environment(\.colorScheme) private var colorScheme
  @State private var containerWidth: CGFloat = 1
  @State private var isShowingSpeedPopover = false
  @State private var selectedDetent = PresentationDetent.medium

  init(viewModel: PlayBarViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    ZStack {
      sheetArtwork

      VStack(spacing: spacing) {
        HStack(spacing: spacing) {
          if viewModel.canExpandTranscript {
            topBarButtonStyle(transcriptDetentButton)
          }

          Spacer()

          if let onDeck = sharedState.onDeck {
            topBarButtonStyle(ShareEpisodeButton(episode: onDeck))
            if viewModel.isTranscriptionAvailable {
              topBarButtonStyle(
                TranscriptionToolbarButton(
                  status: viewModel.transcriptionStatus,
                  transcribe: viewModel.transcribe,
                  pause: viewModel.pauseTranscription
                )
              )
            }
            topBarButtonStyle(ratingMenu(rating: onDeck.rating))
          }
        }
        .padding(.horizontal, spacing)
        .padding(.top, spacing)

        if selectedDetent == .large, let transcript = viewModel.transcript {
          PlayBarTranscriptView(
            transcript: transcript,
            currentTime: viewModel.sliderValue
          )
          .padding(.horizontal, spacing)
          .transition(.opacity)
        } else {
          Spacer()
        }

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
      .animation(
        accessibilityReduceMotion ? nil : .easeInOut(duration: 0.25),
        value: selectedDetent
      )
    }
    .presentationDetents(availableDetents, selection: $selectedDetent)
    .presentationDragIndicator(viewModel.canExpandTranscript ? .visible : .automatic)
    .task(id: sharedState.onDeck?.id) {
      await viewModel.observeTranscriptionCheckpoint()
    }
    .task(id: sharedState.onDeck?.id) {
      await viewModel.observeTranscript()
    }
    .onChange(of: viewModel.canExpandTranscript) { _, canExpandTranscript in
      guard !canExpandTranscript else { return }
      selectedDetent = .medium
    }
  }

  private var availableDetents: Set<PresentationDetent> {
    if viewModel.canExpandTranscript || selectedDetent == .large {
      return [.medium, .large]
    }
    return [.medium]
  }

  private var transcriptDetentButton: some View {
    AppIcon.expandUp
      .imageButton {
        selectedDetent = selectedDetent == .large ? .medium : .large
      }
      .rotationEffect(selectedDetent == .large ? .degrees(180) : .zero)
      .accessibilityLabel(selectedDetent == .large ? "Collapse Transcript" : "Show Transcript")
      .accessibilityValue(selectedDetent == .large ? "Expanded" : "Collapsed")
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
          .accessibilityHidden(true)
      } else {
        (colorScheme == .dark ? Color.black : Color.white)
          .overlay(alignment: .top) {
            AppIcon.audioPlaceholder.image
              .font(.system(size: spacing * 12))
              .padding(.top, spacing * 4)
              .accessibilityHidden(true)
          }
      }
    }
    .ignoresSafeArea()
  }

  private var stopAfterEpisodeButton: some View {
    let icon: AppIcon =
      sharedState.stopAfterCurrentEpisode ? .stopAfterEpisodeOn : .stopAfterEpisode
    return icon.imageButton { viewModel.toggleStopAfterCurrentEpisode() }
      .accessibilityValue(sharedState.stopAfterCurrentEpisode ? "On" : "Off")
  }

  @ViewBuilder
  private func ratingMenu(rating: EpisodeRating?) -> some View {
    let ratingIcon = AppIcon.rating(for: rating)
    Menu {
      ratingMenuButtons(showClear: rating != nil, rate: viewModel.rate)
    } label: {
      ratingIcon.image
    }
    .accessibilityLabel("Rate Episode")
    .accessibilityValue(rating == nil ? "Not Rated" : ratingIcon.text)
  }

  private func topBarButtonStyle<V: View>(_ content: V) -> some View {
    content
      .font(.title3)
      .padding(spacing / 2)
      .glassEffect(.regular.interactive(), in: .capsule)
      .disabled(isShowingSpeedPopover)
  }

  private func metaButtonStyle<V: View>(_ content: V) -> some View {
    content
      .font(.callout)
      .fontWeight(.semibold)
      .fontDesign(.rounded)
      .padding(.horizontal, spacing)
      .padding(.vertical, spacing / 2)
      .glassEffect(.regular.interactive(), in: .capsule)
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
    // With chapters present, give speed/finish/sleep their own row above the
    // centered chapter controls so the row doesn't crowd. Without chapters,
    // the single row is all there is.
    if viewModel.hasChapters {
      VStack(spacing: spacing) {
        metaControlsRow
        chapterControls
      }
    } else {
      metaControlsRow
    }
  }

  private var metaControlsRow: some View {
    HStack {
      metaButtonStyle(
        PlaybackSpeedButton(
          rate: viewModel.playbackRate,
          isShowingPopover: $isShowingSpeedPopover,
          containerWidth: containerWidth
        )
      )

      Spacer()

      HStack(spacing: spacing) {
        metaButtonStyle(finishOrJumpButton)
        metaButtonStyle(stopAfterEpisodeButton)
      }
      .disabled(isShowingSpeedPopover)
    }
  }

  private var chapterControls: some View {
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

  private func playbackButtonStyle<V: View>(_ content: V, font: Font = .title2) -> some View {
    content
      .font(font)
      .padding(spacing / 2)
      .glassEffect(.regular.interactive(), in: .capsule)
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
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Playback Position")
      .accessibilityValue(Text(viewModel.sliderValue.playbackTimeFormat))
      .accessibilityAdjustableAction { direction in
        switch direction {
        case .increment:
          viewModel.seekForward()
        case .decrement:
          viewModel.seekBackward()
        @unknown default:
          break
        }
      }

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
    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: viewModel.isDragging ? 12 : 8))
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
  let transcript: Transcript?

  init(
    _ status: PlaybackStatus = .playing,
    image: UIImage? = PreviewBundle.loadImage(
      named: "pod-save-america-podcast",
      in: .EpisodeThumbnails
    ),
    currentTime: Double = 120,
    maxPlaybackTime: Double = 120,
    duration: Double = 2400,
    description: String? = nil,
    transcript: Transcript? = nil
  ) {
    self.status = status
    self.image = image
    self.currentTimeSeconds = currentTime
    self.maxPlaybackTimeSeconds = maxPlaybackTime
    self.durationSeconds = duration
    self.description = description
    self.transcript = transcript
  }

  var body: some View {
    PlayBarSheet(viewModel: PlayBarViewModel())
      .preview()
      .task {
        Container.shared.transcriptionAvailability().$state.new(.available)
        sharedState.setPlaybackStatus(status)

        let unsavedEpisode = try! Create.unsavedEpisode(
          duration: CMTime.seconds(durationSeconds),
          description: description
        )
        var podcastEpisode = try! await Create.podcastEpisode(unsavedEpisode)
        if let transcript {
          try! await Container.shared.repo()
            .updateTranscript(
              podcastEpisode.id,
              transcript: transcript.jsonString()
            )
          guard
            let updatedPodcastEpisode = try! await Container.shared.repo()
              .podcastEpisode(podcastEpisode.id)
          else { return }
          podcastEpisode = updatedPodcastEpisode
        }
        var onDeck = OnDeck(from: podcastEpisode)
        onDeck.artwork = image
        onDeck.currentTime = CMTime.seconds(currentTimeSeconds)
        onDeck.maxPlaybackTime = CMTime.seconds(maxPlaybackTimeSeconds)
        sharedState.$onDeck.new(onDeck)
      }
  }
}

#Preview("at peak — transcription + finish") {
  PlayBarSheetPreview(currentTime: 600, maxPlaybackTime: 600)
}

#Preview("transcript — tap expand") {
  PlayBarSheetPreview(
    currentTime: 3,
    maxPlaybackTime: 3,
    duration: 12,
    transcript: Transcript(
      segments: [
        TranscriptSegment(
          start: 0,
          end: 6,
          text: "The highlighted word follows the episode.",
          words: [
            TranscriptWord(start: 0, end: 1, text: "The"),
            TranscriptWord(start: 1, end: 2, text: " highlighted"),
            TranscriptWord(start: 2, end: 3.5, text: " word"),
            TranscriptWord(start: 3.5, end: 4.5, text: " follows"),
            TranscriptWord(start: 4.5, end: 5, text: " the"),
            TranscriptWord(start: 5, end: 6, text: " episode."),
          ]
        ),
        TranscriptSegment(start: 6, end: 12, text: "Swipe between medium and full height."),
      ],
      locale: "en-US",
      createdAt: Date()
    )
  )
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
