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

  subscript<T>(dynamicMember keyPath: KeyPath<PlayState.Status, T>) -> T {
    status[keyPath: keyPath]
  }

  // MARK: - State Getters

  enum Status {
    case loading(String)
    case paused, playing, seeking, stopped, waiting

    var playable: Bool {
      switch self {
      case .stopped: return false
      default: return true
      }
    }

    var loading: String? {
      if case .loading(let title) = self { return title }
      return nil
    }

    var playing: Bool {
      if case .playing = self { return true }
      return false
    }

    var paused: Bool {
      if case .paused = self { return true }
      return false
    }

    var stopped: Bool {
      if case .stopped = self { return true }
      return false
    }

    var waiting: Bool {
      if case .waiting = self { return true }
      return false
    }
  }

  private(set) var status: Status = .stopped
  private(set) var currentTime = CMTime.zero
  private(set) var onDeck: OnDeck?

  private var keyboardVisible = false

  var showPlayBar: Bool {
    !keyboardVisible && status.playable
  }

  // MARK: - State Setters

  func setStatus(_ status: Status) {
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
