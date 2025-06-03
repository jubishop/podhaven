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
    case loading, active, playing, paused, stopped, waiting

    var playable: Bool {
      switch self {
      case .active, .playing, .paused, .waiting: return true
      default: return false
      }
    }

    var loading: Bool { self == .loading }
    var active: Bool { self == .active }
    var playing: Bool { self == .playing }
    var paused: Bool { self == .paused }
    var stopped: Bool { self == .stopped }
    var waiting: Bool { self == .waiting }
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

    Task {
      for await _ in notifications(UIResponder.keyboardWillShowNotification) {
        keyboardVisible = true
      }
    }
  }

  private func startListeningToKeyboardHide() {
    Assert.neverCalled()

    Task {
      for await _ in notifications(UIResponder.keyboardDidHideNotification) {
        keyboardVisible = false
      }
    }
  }
}
