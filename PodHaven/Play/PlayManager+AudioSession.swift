// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation
import Logging

extension Container {
  // Retries because mediaservicesd is sometimes dead at launch (e.g., right
  // after a TestFlight install/update) and typically respawns within seconds.
  var configureAudioSession: Factory<@Sendable () async -> Bool> {
    Factory(self) {
      {
        PlayManager.log.info("configureAudioSession: executing")

        let maxAttempts = 5
        let maxDelay: Duration = .seconds(2)
        var retryDelay: Duration = .milliseconds(250)

        for attempt in 1...maxAttempts {
          do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)
            try session.setMode(.spokenAudio)
            PlayManager.log.info(
              """
              configureAudioSession: configured (attempt \(attempt)/\(maxAttempts))
                category: \(session.category.rawValue)
                mode: \(session.mode.rawValue)
                routeSharingPolicy: \(session.routeSharingPolicy.rawValue)
              """
            )
            return true
          } catch {
            if attempt == maxAttempts {
              PlayManager.log.caughtError(
                "configureAudioSession: failed after \(maxAttempts) attempts",
                error
              )
              await Container.shared.alert()(
                title: "Couldn't start audio playback",
                ErrorKit.message(for: error)
              )
              return false
            }
            PlayManager.log.debug(
              """
              configureAudioSession: attempt \(attempt)/\(maxAttempts) failed, \
              retrying in \(retryDelay)
                error: \(ErrorKit.message(for: error))
              """
            )
            do {
              try await Container.shared.sleeper().sleep(for: retryDelay)
            } catch {
              PlayManager.log.caughtError(
                """
                configureAudioSession: cancelled during retry backoff \
                (attempt \(attempt)/\(maxAttempts))
                """,
                error
              )
              return false
            }
            retryDelay = min(retryDelay * 2, maxDelay)
          }
        }
        return false
      }
    }
    .scope(.cached)
  }

  var setAudioSessionActive: Factory<(Bool) throws -> Void> {
    Factory(self) {
      { active in
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setActive(active)
      }
    }
  }
}

@globalActor
actor PlayActor {
  static let shared = PlayActor()
}
