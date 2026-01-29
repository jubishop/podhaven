// Copyright Justin Bishop, 2025

import CoreMedia
import SwiftUI

struct PlayBarSheet: View {
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
        HStack {
          Spacer()

          if let shareURL = viewModel.shareURL {
            ShareLink(
              item: shareURL,
              preview: viewModel.sharePreview,
              label: { AppIcon.shareEpisode.image }
            )
            .font(.title3)
            .padding(spacing / 2)
            .glassEffect(.clear.interactive(), in: .capsule)
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
        .animation(.easeInOut(duration: 0.2), value: viewModel.showUndoButton)

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
        Color.black
          .overlay(alignment: .top) {
            AppIcon.audioPlaceholder.image
              .font(.system(size: spacing * 12))
              .padding(.top, spacing * 4)
          }
      }
    }
    .ignoresSafeArea()
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
  private var playbackMetaControls: some View {
    metaButtonStyle(
      PlaybackSpeedButton(
        rate: viewModel.playbackRate,
        isShowingPopover: $isShowingSpeedPopover,
        containerWidth: containerWidth
      )
    )

    Spacer()

    metaButtonStyle(
      AppIcon.finishEpisode
        .imageButton {
          viewModel.finishEpisode()
        }
    )
    .disabled(isShowingSpeedPopover)
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

    if viewModel.showUndoButton {
      playbackButtonStyle(AppIcon.undoSeek.imageButton(action: viewModel.undoSeek))
    } else {
      playbackButtonStyle(SeekBackwardButton(action: viewModel.seekBackward))
    }

    Spacer()

    playbackButtonStyle(PlayPauseButton(action: viewModel.playOrPause), font: .title)

    Spacer()

    playbackButtonStyle(SeekForwardButton(action: viewModel.seekForward))

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
        animationDuration: progressAnimationDuration
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
