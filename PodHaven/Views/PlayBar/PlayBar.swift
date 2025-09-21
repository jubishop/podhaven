// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

struct PlayBar: View {
  @Environment(\.colorScheme) private var colorScheme
  @InjectedObservable(\.playBarViewModel) private var viewModel

  private let imageSize: CGFloat = 48
  private let horizontalPadding: CGFloat = 16
  private let verticalPadding: CGFloat = 10
  private let containerCornerRadius: CGFloat = 12
  private let outerHorizontalInset: CGFloat = 16
  private let barSpacing: CGFloat = 8
  private let transportSpacing: CGFloat = 16
  private let primaryControlSize: CGFloat = 24
  private let secondaryControlSize: CGFloat = 30

  var body: some View {
    playBarContent
      .padding(.horizontal, horizontalPadding)
      .padding(.vertical, verticalPadding)
      .glassEffect(containerGlass)
      .frame(maxWidth: .infinity)
      .padding(.horizontal, outerHorizontalInset)
  }

  @ViewBuilder
  private var playBarContent: some View {
    if viewModel.isLoading {
      loadingContent
    } else if viewModel.isStopped {
      stoppedContent
    } else if viewModel.isExpanded {
      expandedContent
    } else {
      collapsedContent
    }
  }

  private var loadingContent: some View {
    HStack(spacing: viewModel.commonSpacing) {
      ProgressView()
        .controlSize(.small)
        .tint(.secondary)

      Text("Loading \(viewModel.loadingEpisodeTitle)")
        .font(.callout.weight(.semibold))
        .foregroundStyle(.primary)
        .lineLimit(1)

      Spacer()
    }
  }

  private var stoppedContent: some View {
    HStack(spacing: viewModel.commonSpacing) {
      AppLabel.noEpisodeSelected.image
        .symbolRenderingMode(.hierarchical)
        .font(.system(size: 24, weight: .medium))
        .foregroundStyle(.secondary)

      Text("No episode selected")
        .font(.callout.weight(.semibold))
        .foregroundStyle(.secondary)

      Spacer()
    }
  }

  private var collapsedContent: some View {
    HStack(spacing: barSpacing) {
      episodeImage

      Spacer()

      transportControls

      Spacer()

      expandButton(direction: viewModel.isExpanded ? .down : .up)
    }
  }

  private var expandedContent: some View {
    VStack(spacing: 16) {
      collapsedContent

      VStack(spacing: 10) {
        CustomProgressBar(
          value: $viewModel.sliderValue,
          isDragging: $viewModel.isDragging,
          range: 0...Double(viewModel.duration.seconds),
          animationDuration: viewModel.progressAnimationDuration
        )

        HStack {
          Text(viewModel.sliderValue.playbackTimeFormat)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)

          Spacer()

          Text(viewModel.duration.seconds.playbackTimeFormat)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  private var episodeImage: some View {
    Button(action: viewModel.showEpisodeDetail) {
      Group {
        if let image = viewModel.episodeImage {
          Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: imageSize, height: imageSize)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(.clear)
            .frame(width: imageSize, height: imageSize)
            .overlay {
              AppLabel.audioPlaceholder.image
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            }
            .glassEffect(
              Glass.regular
                .tint(Color.secondary.opacity(colorScheme == .dark ? 0.45 : 0.28))
                .interactive(),
              in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
        }
      }
      .shadow(color: shadowColor.opacity(0.3), radius: 6, y: 6)
    }
    .buttonStyle(.plain)
  }

  private var transportControls: some View {
    HStack(spacing: transportSpacing) {
      glassControlButton(
        icon: viewModel.seekBackwardImage,
        size: secondaryControlSize,
        tint: .primary.opacity(0.75),
        action: viewModel.seekBackward
      )

      Button(action: viewModel.playOrPause) {
        Group {
          if viewModel.isWaiting {
            AppLabel.loading.image
              .symbolRenderingMode(.hierarchical)
              .foregroundStyle(.primary.opacity(0.8))
              .font(.system(size: 18, weight: .medium))
          } else if viewModel.isPlaying {
            AppLabel.pauseButton.image
              .symbolRenderingMode(.hierarchical)
              .foregroundStyle(.primary)
              .font(.system(size: 20, weight: .semibold))
          } else {
            AppLabel.playButton.image
              .symbolRenderingMode(.hierarchical)
              .foregroundStyle(.primary)
              .font(.system(size: 22, weight: .semibold))
          }
        }
        .frame(width: primaryControlSize, height: primaryControlSize)
      }
      .buttonStyle(.glassProminent)
      .buttonBorderShape(.capsule)
      .tint(Color.accentColor)

      glassControlButton(
        icon: viewModel.seekForwardImage,
        size: secondaryControlSize,
        tint: .primary.opacity(0.75),
        action: viewModel.seekForward
      )
    }
  }

  private func expandButton(direction: ExpansionDirection) -> some View {
    Button(action: viewModel.toggleExpansion) {
      direction.image
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(.secondary)
        .font(.system(size: 18, weight: .semibold))
        .frame(width: secondaryControlSize, height: secondaryControlSize)
    }
    .buttonStyle(.glass)
    .buttonBorderShape(.capsule)
    .tint(.secondary.opacity(0.8))
  }

  private func glassControlButton(
    icon: Image,
    size: CGFloat,
    tint: Color,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      icon
        .symbolRenderingMode(.hierarchical)
        .font(.system(size: 16, weight: .semibold))
        .frame(width: size, height: size)
    }
    .buttonStyle(.glass)
    .buttonBorderShape(.capsule)
    .tint(tint)
  }

  private enum ExpansionDirection {
    case up
    case down

    var image: Image {
      switch self {
      case .up:
        return AppLabel.expandUp.image
      case .down:
        return AppLabel.expandDown.image
      }
    }
  }

  private var containerGlass: Glass {
    Glass.regular
      .interactive()
  }

  private var containerTint: Color {
    colorScheme == .dark
      ? Color.accentColor.opacity(0.42)
      : Color.accentColor.opacity(0.28)
  }

  private var shadowColor: Color {
    colorScheme == .dark
      ? Color.black.opacity(0.45)
      : Color(.sRGBLinear, red: 0, green: 0, blue: 0, opacity: 0.12)
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
