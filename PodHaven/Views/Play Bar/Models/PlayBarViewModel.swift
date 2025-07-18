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
  @ObservationIgnored @DynamicInjected(\.playManager) private var playManager
  @ObservationIgnored @DynamicInjected(\.playState) private var playState

  // MARK: - Constants

  let progressAnimationDuration: Double = 0.15
  let progressDragScale: Double = 1.1
  let expansionAnimationDuration: Double = 0.25
  let commonSpacing: CGFloat = 12
  let textFont: Font = .system(size: 16, weight: .medium)

  // MARK: - State Management

  var isLoading: Bool { playState.loading }
  var isPlaying: Bool { playState.playing }
  var isSeeking: Bool { playState.seeking }
  var isStopped: Bool { playState.stopped }
  var isWaiting: Bool { playState.waiting }

  var duration: CMTime { playState.onDeck?.duration ?? CMTime.zero }
  var episodeImage: UIImage? { playState.onDeck?.image }
  var episodeTitle: String? { playState.onDeck?.episodeTitle }
  var loadingEpisodeTitle: String { playState.loadingTitle ?? "Unknown" }
  var podcastTitle: String? { playState.onDeck?.podcastTitle }
  var publishedAt: Date? { playState.onDeck?.pubDate }

  var isExpanded = false
  var isDragging = false

  private var _sliderValue: Double = 0
  var sliderValue: Double {
    get { isDragging ? _sliderValue : playState.currentTime.seconds }
    set {
      self._sliderValue = newValue
      Task { [weak self] in
        guard let self else { return }
        await playManager.seek(to: CMTime.inSeconds(_sliderValue))
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
      await playManager.seekBackward(CMTime.inSeconds(15))
    }
  }

  func seekForward() {
    Task { [weak self] in
      guard let self else { return }
      await playManager.seekForward(CMTime.inSeconds(30))
    }
  }
}
