// Copyright Justin Bishop, 2025

import SwiftUI

struct PlayBarSheet: View {
  private let spacing: CGFloat = 12

  @Bindable var viewModel: PlayBarViewModel

  init(viewModel: PlayBarViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    ZStack {
      sheetArtwork

      VStack(spacing: spacing) {
        Spacer()

        HStack {
          Spacer()

          playbackControls

          Spacer()
        }

        progressBar
          .padding(.horizontal, spacing)
      }
      .padding(.horizontal, spacing)
    }
    .presentationDetents([.medium])
  }

  @ViewBuilder
  private var sheetArtwork: some View {
    Group {
      if let image = viewModel.episodeImage {
        Color.black
          .overlay(alignment: .center) {
            Image(uiImage: image)
              .resizable()
              .scaledToFill()
          }
          .overlay {
            LinearGradient(
              colors: [
                .black.opacity(0),
                .black.opacity(0.25),
                .black.opacity(0.75),
              ],
              startPoint: .top,
              endPoint: .bottom
            )
          }
      } else {
        Color.black
          .overlay(alignment: .top) {
            AppIcon.audioPlaceholder.coloredImage
              .font(.system(size: spacing * 12))
              .padding(.top, spacing * 4)
          }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .clipped()
    .ignoresSafeArea()
  }

  @ViewBuilder
  private var playbackControls: some View {
    Spacer()

    AppIcon.seekBackward.imageButton(action: viewModel.seekBackward)
      .font(.title2)
      .buttonStyle(.glass)

    Spacer()

    PlayPauseButton(action: viewModel.playOrPause)
      .font(.title)
      .buttonStyle(.glass)

    Spacer()

    AppIcon.seekForward.imageButton(action: viewModel.seekForward)
      .font(.title2)
      .buttonStyle(.glass)

    Spacer()
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
}
