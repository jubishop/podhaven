// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation
import SwiftUI

extension Container {
  @MainActor var playState: Factory<PlayState> {
    Factory(self) { @MainActor in PlayState() }.scope(.cached)
  }
}

@dynamicMemberLookup @Observable @MainActor class PlayState {
  @ObservationIgnored @DynamicInjected(\.notifications) private var notifications

  // MARK: - Meta

  subscript<T>(dynamicMember keyPath: KeyPath<PlaybackStatus, T>) -> T {
    status[keyPath: keyPath]
  }

  // MARK: - State Getters

  private(set) var status: PlaybackStatus = .stopped
  private(set) var currentTime = CMTime.zero
  private(set) var onDeck: OnDeck?

  private var keyboardVisible = false
  var showPlayBar: Bool { !keyboardVisible }

  func isEpisodePlaying(_ episode: any EpisodeInformable) -> Bool {
    guard let episodeID = episode.episodeID else { return false }
    return isEpisodePlaying(episodeID)
  }
  func isEpisodePlaying(_ episodeID: Episode.ID) -> Bool {
    guard status.playing, let onDeck else { return false }
    return onDeck.episodeID == episodeID
  }

  // MARK: - State Setters

  func setStatus(_ status: PlaybackStatus) {
    self.status = status
  }

  func setCurrentTime(_ currentTime: CMTime) {
    self.currentTime = currentTime
  }

  func setOnDeck(_ onDeck: OnDeck?) {
    self.onDeck = onDeck
  }

  // MARK: - Initialization

  fileprivate init() {
    startListeningToKeyboardShow()
    startListeningToKeyboardHide()
  }

  private func startListeningToKeyboardShow() {
    Assert.neverCalled()

    Task { [weak self] in
      guard let self else { return }
      for await _ in notifications(UIResponder.keyboardWillShowNotification) {
        keyboardVisible = true
      }
    }
  }

  private func startListeningToKeyboardHide() {
    Assert.neverCalled()

    Task { [weak self] in
      guard let self else { return }
      for await _ in notifications(UIResponder.keyboardDidHideNotification) {
        keyboardVisible = false
      }
    }
  }
}
