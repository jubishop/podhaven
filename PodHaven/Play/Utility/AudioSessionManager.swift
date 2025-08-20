// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation
import Logging

extension Container {
  var audioSessionManager: Factory<AudioSessionManager> {
    Factory(self) { @PlayActor in AudioSessionManager() }.scope(.cached)
  }
}

/// Manages audio session configuration and handles media services resets
@PlayActor
final class AudioSessionManager {
  @DynamicInjected(\.notifications) private var notifications

  nonisolated private static let log = Log.as(LogSubsystem.Play.audioSession)

  // MARK: - Configuration

  private let category: AVAudioSession.Category = .playback
  private let mode: AVAudioSession.Mode = .spokenAudio
  private let policy: AVAudioSession.RouteSharingPolicy = .longFormAudio

  // MARK: - State Management

  private var mediaServicesResetTask: Task<Void, Never>?

  // MARK: - Initialization

  fileprivate init() {}

  /// Configures the audio session for podcast playback
  func configure() throws {
    Self.log.debug("configure: configuring audio session")
    let audioSession = AVAudioSession.sharedInstance()

    try audioSession.setCategory(category, mode: mode, policy: policy)
    try audioSession.setMode(mode)
    try audioSession.setActive(true)

    Self.log.debug("configure: audio session configured successfully")

    // Start monitoring for media services reset
    startMediaServicesResetMonitoring()
  }

  /// Starts monitoring for media services reset notifications
  private func startMediaServicesResetMonitoring() {
    guard mediaServicesResetTask == nil else { return }

    Self.log.debug("startMediaServicesResetMonitoring: starting monitoring")

    mediaServicesResetTask = Task { [weak self] in
      guard let self else { return }

      for await _ in notifications(AVAudioSession.mediaServicesWereResetNotification) {
        Self.log.warning("Media services were reset - attempting recovery")
        await handleMediaServicesReset()
      }
    }
  }

  /// Handles recovery from media services reset
  private func handleMediaServicesReset() async {
    Self.log.info("handleMediaServicesReset: beginning recovery")

    // Attempt to reconfigure the audio session
    do {
      try configure()
      Self.log.info("handleMediaServicesReset: audio session recovery successful")
    } catch {
      Self.log.error(error)
    }
  }
}
