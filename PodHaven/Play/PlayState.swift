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
  @ObservationIgnored @DynamicInjected(\.observatory) private var observatory

  private static let log = Log.as(LogSubsystem.Play.state)

  // MARK: - Meta

  subscript<T>(dynamicMember keyPath: KeyPath<PlaybackStatus, T>) -> T {
    status[keyPath: keyPath]
  }

  // MARK: - Private State

  private var keyboardVisible = false

  // MARK: - State Getters

  private(set) var status: PlaybackStatus = .stopped
  private(set) var currentTime = CMTime.zero
  private(set) var onDeck: OnDeck?
  private(set) var maxQueuePosition: Int? = nil

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
    startObservingMaxQueuePosition()
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

  private func startObservingMaxQueuePosition() {
    Assert.neverCalled()

    Task { [weak self] in
      guard let self else { return }
      for try await maxQueuePosition in self.observatory.maxQueuePosition() {
        Self.log.debug(
          "Updating observed max queue position: \(String(describing: maxQueuePosition))"
        )
        self.maxQueuePosition = maxQueuePosition
      }
    }
  }
}
