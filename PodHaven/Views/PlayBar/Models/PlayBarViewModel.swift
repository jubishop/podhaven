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

  private static let log = Log.as(LogSubsystem.PlayBar.main)

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

  // MARK: - Actions

  func toggleExpansion() {
    Self.log.debug("Toggling expansion")
    withAnimation {
      isExpanded.toggle()
    }
  }

  func showEpisodeDetail() {
    Task { [weak self] in
      guard let self else { return }
      do {
        Self.log.debug("Showing episode detail")
        try await presentEpisodeDetail()
      } catch {
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.coreMessage(for: error))
      }
    }
  }

  private func presentEpisodeDetail() async throws {
    guard let onDeck = playState.onDeck,
      let podcastEpisode = try await repo.podcastEpisode(onDeck.episodeID)
    else { return }

    sheet {
      EpisodeDetailView(viewModel: EpisodeDetailViewModel(episode: podcastEpisode))
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
      Self.log.debug("Seeking backward")
      await playManager.seekBackward(CMTime.seconds(15))
    }
  }

  func seekForward() {
    Task { [weak self] in
      guard let self else { return }
      Self.log.debug("Seeking forward")
      await playManager.seekForward(CMTime.seconds(30))
    }
  }
}
