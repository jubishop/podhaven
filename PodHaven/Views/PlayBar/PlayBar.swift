// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

struct PlayBar: View {
  @Environment(\.colorScheme) private var colorScheme
  @InjectedObservable(\.playBarViewModel) private var viewModel

  private let imageSize: CGFloat = 48
  private let horizontalPadding: CGFloat = 20
  private let verticalPadding: CGFloat = 14
  private let glassCornerRadius: CGFloat = 26
  private let controlSize: CGFloat = 44
  private let secondaryControlSize: CGFloat = 36
  private let barSpacing: CGFloat = 12
  private let transportSpacing: CGFloat = 24

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
    .padding(.horizontal, horizontalPadding)
    .padding(.vertical, verticalPadding)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(glassBackground)
    .clipShape(glassShape)
    .overlay(glassStroke)
    .overlay(glassSpecularHighlight)
    .shadow(color: shadowColor, radius: 20, y: 14)
    .padding(.horizontal, 16)
  }

  // MARK: - Loading PlayBar

  private var loadingPlayBar: some View {
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

  // MARK: - Stopped PlayBar

  private var stoppedPlayBar: some View {
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

  // MARK: - Collapsed PlayBar

  private var collapsedPlayBar: some View {
    HStack(alignment: .center, spacing: barSpacing) {
      episodeImage

      Spacer()

      transportControls

      Spacer(minLength: barSpacing)

      expandButton(direction: .up)
    }
  }

  // MARK: - Expanded PlayBar

  private var expandedPlayBar: some View {
    VStack(spacing: 18) {
      HStack(alignment: .center, spacing: barSpacing) {
        episodeImage

        Spacer()

        transportControls

        Spacer(minLength: barSpacing)

        expandButton(direction: .down)
      }

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
            .scaleEffect(viewModel.isDragging ? viewModel.progressDragScale : 1.0)
            .animation(
              .easeInOut(duration: viewModel.progressAnimationDuration),
              value: viewModel.isDragging
            )

          Spacer()

          Text(viewModel.duration.seconds.playbackTimeFormat)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
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
    Button(action: viewModel.showEpisodeDetail) {
      Group {
        if let image = viewModel.episodeImage {
          Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: imageSize, height: imageSize)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.secondary.opacity(colorScheme == .dark ? 0.28 : 0.2))
            .frame(width: imageSize, height: imageSize)
            .overlay {
              AppLabel.audioPlaceholder.image
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            }
        }
      }
      .shadow(color: shadowColor.opacity(0.3), radius: 14, y: 8)
    }
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
              .foregroundStyle(.white.opacity(0.8))
              .font(.system(size: 20, weight: .medium))
          } else if viewModel.isPlaying {
            AppLabel.pauseButton.image
              .symbolRenderingMode(.hierarchical)
              .foregroundStyle(.white)
              .font(.system(size: 22, weight: .semibold))
          } else {
            AppLabel.playButton.image
              .symbolRenderingMode(.hierarchical)
              .foregroundStyle(.white)
              .font(.system(size: 24, weight: .semibold))
          }
        }
        .frame(width: controlSize, height: controlSize)
        .background(playButtonBackground)
        .overlay(playButtonStroke)
        .shadow(color: shadowColor.opacity(0.22), radius: 16, y: 8)
      }
      .buttonStyle(.plain)

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
        .background(glassControlBackground.opacity(0.7), in: Capsule())
        .overlay(
          Capsule()
            .strokeBorder(glassControlStroke, lineWidth: 1)
        )
    }
    .buttonStyle(.plain)
  }

  private var glassBackground: some View {
    glassShape
      .fill(.thinMaterial)
      .overlay {
        glassShape
          .fill(
            LinearGradient(
              colors: [
                Color.accentColor.opacity(colorScheme == .dark ? 0.3 : 0.2),
                Color.accentColor.opacity(0.04),
              ],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
          .opacity(0.5)
      }
  }

  private var glassStroke: some View {
    glassShape
      .strokeBorder(
        LinearGradient(
          colors: [
            Color.white.opacity(colorScheme == .dark ? 0.34 : 0.18),
            Color.white.opacity(colorScheme == .dark ? 0.12 : 0.04),
          ],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      )
  }

  private var glassSpecularHighlight: some View {
    ZStack(alignment: .topLeading) {
      glassShape
        .strokeBorder(
          LinearGradient(
            colors: [
              Color.white.opacity(colorScheme == .dark ? 0.22 : 0.3),
              Color.clear,
            ],
            startPoint: .top,
            endPoint: .bottom
          ),
          lineWidth: 1
        )

      LinearGradient(
        colors: [
          Color.white.opacity(colorScheme == .dark ? 0.16 : 0.24),
          Color.clear,
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      .frame(height: 6)
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    .clipShape(glassShape)
    .allowsHitTesting(false)
  }

  private var glassShape: RoundedRectangle {
    RoundedRectangle(cornerRadius: glassCornerRadius, style: .continuous)
  }

  private var playButtonBackground: some View {
    Capsule(style: .continuous)
      .fill(
        LinearGradient(
          colors: [
            Color.accentColor.opacity(colorScheme == .dark ? 0.85 : 0.9),
            Color.accentColor.opacity(colorScheme == .dark ? 0.65 : 0.6),
          ],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      )
  }

  private var playButtonStroke: some View {
    Capsule(style: .continuous)
      .strokeBorder(
        LinearGradient(
          colors: [
            Color.white.opacity(colorScheme == .dark ? 0.3 : 0.45),
            Color.white.opacity(colorScheme == .dark ? 0.08 : 0.16),
          ],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        ),
        lineWidth: 1
      )
  }

  private var glassControlBackground: some ShapeStyle {
    LinearGradient(
      colors: [
        Color.white.opacity(colorScheme == .dark ? 0.15 : 0.18),
        Color.white.opacity(colorScheme == .dark ? 0.05 : 0.08),
      ],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
  }

  private var glassControlStroke: LinearGradient {
    LinearGradient(
      colors: [
        Color.white.opacity(colorScheme == .dark ? 0.28 : 0.24),
        Color.white.opacity(colorScheme == .dark ? 0.06 : 0.08),
      ],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
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
        .foregroundStyle(tint)
        .font(.system(size: 18, weight: .semibold))
        .frame(width: size, height: size)
        .background(glassControlBackground, in: Capsule(style: .continuous))
        .overlay(
          Capsule(style: .continuous)
            .strokeBorder(glassControlStroke, lineWidth: 1)
        )
    }
    .buttonStyle(.plain)
    .shadow(color: shadowColor.opacity(0.18), radius: 10, y: 4)
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

  private var shadowColor: Color {
    colorScheme == .dark
      ? Color.black.opacity(0.45) : Color(.sRGBLinear, red: 0, green: 0, blue: 0, opacity: 0.12)
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
