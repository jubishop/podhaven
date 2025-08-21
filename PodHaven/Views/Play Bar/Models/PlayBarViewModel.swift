// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation
import SwiftUI

extension Container {
  @MainActor var playBarViewModel: Factory<PlayBarViewModel> {
    Factory(self) { @MainActor in PlayBarViewModel() }.scope(.cached)
  }
}

@Observable @MainActor class PlayBarViewModel {
  @ObservationIgnored @DynamicInjected(\.alert) private var alert
  @ObservationIgnored @DynamicInjected(\.playManager) private var playManager
  @ObservationIgnored @DynamicInjected(\.playState) var playState
  @ObservationIgnored @DynamicInjected(\.repo) private var repo
  @ObservationIgnored @DynamicInjected(\.sheet) private var sheet

  // MARK: - Constants

  let progressAnimationDuration: Double = 0.15
  let progressDragScale: Double = 1.1
  let expansionAnimationDuration: Double = 0.25
  let commonSpacing: CGFloat = 12
  let textFont: Font = .system(size: 16, weight: .medium)

  // MARK: - State Management

  var isLoading: Bool { playState.loading }
  var isPlaying: Bool { playState.playing }
  var isStopped: Bool { playState.stopped }
  var isWaiting: Bool { playState.waiting }

  var duration: CMTime { playState.onDeck?.duration ?? CMTime.zero }
  var episodeImage: UIImage? { playState.onDeck?.image }
  var loadingEpisodeTitle: String { playState.loadingTitle ?? "Unknown" }

  var isExpanded = false
  var isDragging = false

  private var _sliderValue: Double = 0
  var sliderValue: Double {
    get { isDragging ? _sliderValue : playState.currentTime.seconds }
    set {
      self._sliderValue = newValue
      Task { [weak self] in
        guard let self else { return }
        await playManager.seek(to: CMTime.seconds(_sliderValue))
      }
    }
  }

  var seekBackwardImage: Image { Image(systemName: "gobackward.15") }
  var seekForwardImage: Image { Image(systemName: "goforward.30") }

  // MARK: - Actions

  func toggleExpansion() {
    withAnimation(.easeInOut(duration: expansionAnimationDuration)) {
      isExpanded.toggle()
    }
  }

  func showEpisodeDetail() {
    Task { [weak self] in
      guard let self else { return }
      do {
        try await presentEpisodeDetail()
      } catch {
        alert(ErrorKit.message(for: error))
      }
    }
  }

  private func presentEpisodeDetail() async throws {
    guard let onDeck = playState.onDeck,
      let podcastEpisode = try await repo.podcastEpisode(onDeck.episodeID)
    else { return }

    sheet {
      EpisodeDetailView(viewModel: EpisodeDetailViewModel(podcastEpisode: podcastEpisode))
    }
  }

  func playOrPause() {
    if isPlaying {
      Task { [weak self] in
        guard let self else { return }
        await playManager.pause()
      }
    } else {
      Task { [weak self] in
        guard let self else { return }
        await playManager.play()
      }
    }
  }

  func seekBackward() {
    Task { [weak self] in
      guard let self else { return }
      await playManager.seekBackward(CMTime.seconds(15))
    }
  }

  func seekForward() {
    Task { [weak self] in
      guard let self else { return }
      await playManager.seekForward(CMTime.seconds(30))
    }
  }
}
