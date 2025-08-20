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

/// Manages audio session configuration
@PlayActor
final class AudioSessionManager {
  @DynamicInjected(\.notifications) private var notifications

  nonisolated private static let log = Log.as(LogSubsystem.Play.audioSession)

  // MARK: - Configuration

  private let category: AVAudioSession.Category = .playback
  private let mode: AVAudioSession.Mode = .spokenAudio
  private let policy: AVAudioSession.RouteSharingPolicy = .longFormAudio

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
  }
}
