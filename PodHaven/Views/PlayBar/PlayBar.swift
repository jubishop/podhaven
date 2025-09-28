// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import SwiftUI

// Eventually we should replace this with TabViewBottomAccessoryPlacement
struct PlayBarAccessory: View {
  nonisolated static let CoordinateName = "TabRoot"

  @State private var accessoryMaxY: CGFloat = 0
  @State private var tabMaxY: CGFloat
  @State private var isExpanded = true

  init(tabMaxY: CGFloat) {
    self.tabMaxY = tabMaxY
  }

  var body: some View {
    PlayBar(isExpanded: isExpanded)
      .onGeometryChange(for: CGFloat.self) { proxy in
        proxy.frame(in: .named(Self.CoordinateName)).maxY
      } action: { newMaxY in
        accessoryMaxY = newMaxY
        isExpanded = (tabMaxY - newMaxY) > 40
      }
  }
}

struct PlayBar: View {
  private let basicSpacing: CGFloat = 12

  private let viewModel = PlayBarViewModel()

  private let isExpanded: Bool

  init(isExpanded: Bool) {
    self.isExpanded = isExpanded
  }

  var body: some View {
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
  }

  // MARK: - Stopped PlayBar

  private var stoppedPlayBar: some View {
    HStack(spacing: basicSpacing) {
      AppIcon.noEpisodeSelected.coloredImage

      Text("No episode selected")
        .foregroundColor(.white)

      Spacer()
    }
    .padding(12)
  }

  // MARK: - Inline PlayBar

  private var inlinePlayBar: some View {
    playbackControls
  }

  // MARK: - Progress Bar

  private var expandedPlayBar: some View {
    HStack {
      episodeImage

      Spacer()

      playbackControls

      Spacer()

      sheetControlsButton
    }
  }

  // MARK: - Shared Components

  private var episodeImage: some View {
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
            .fill(Color.white.opacity(0.2))
            .overlay(
              AppIcon.audioPlaceholder.coloredImage
            )
        }
      }
    )
  }

  private var playbackControls: some View {
    HStack(spacing: 12) {
      AppIcon.seekBackward.imageButton(action: viewModel.seekBackward)
        .font(.title2)

      playPauseButton
        .font(.title)

      AppIcon.seekForward.imageButton(action: viewModel.seekForward)
        .font(.title2)
    }
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

  @ViewBuilder
  private var sheetControlsButton: some View {
    AppIcon.expandUp.imageButton(action: viewModel.showControlSheet)
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
            .frame(width: 32, height: 32)
        }
      )

      AppIcon.loading.imageButton {
        Container.shared.playState().setStatus(.waiting)
      }

      AppIcon.pauseButton.imageButton {
        Container.shared.playState().setStatus(.playing)
      }

      AppIcon.playButton.imageButton {
        Container.shared.playState().setStatus(.paused)
      }

      AppIcon.noEpisodeSelected.imageButton {
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

      // TODO: Give button to flip isExpanded
      PlayBar(isExpanded: true)
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
