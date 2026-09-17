// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Logging

extension Container {
  @MainActor var carPlaySelection: Factory<CarPlaySelection> {
    Factory(self) { CarPlaySelection() }
  }
}

@MainActor
final class CarPlaySelection {
  private final class Request {
    let playbackID = UUID()
    let episodeID: Episode.ID
    var completions: [() -> Void]
    var work: Task<Void, Never>?
    var deadline: Task<Void, Never>?
    var replacement: Task<Void, Never>?

    init(_ episodeID: Episode.ID, completion: @escaping () -> Void) {
      self.episodeID = episodeID
      completions = [completion]
    }

    func finish() {
      work?.cancel()
      deadline?.cancel()
      replacement?.cancel()
      work = nil
      deadline = nil
      replacement = nil
      let callbacks = completions
      completions = []
      for callback in callbacks { callback() }
    }
  }

  @DynamicInjected(\.appLauncher) private var appLauncher
  @DynamicInjected(\.playManager) private var playManager
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.sharedState) private var sharedState
  @DynamicInjected(\.sleeper) private var sleeper
  private static let log = Log.as("CarPlaySelection")
  private enum ConnectionState { case connected, disconnected }
  private var connectionState = ConnectionState.disconnected
  private var request: Request?
  var showNowPlaying: (() -> Void)?
  var showError: ((String) -> Void)?

  fileprivate init() {}

  func connect() { connectionState = .connected }

  func select(_ episodeID: Episode.ID, completion: @escaping () -> Void) {
    guard connectionState == .connected else {
      completion()
      return
    }
    if let request, request.episodeID == episodeID {
      request.completions.append(completion)
      return
    }
    cancel()
    let request = Request(episodeID, completion: completion)
    self.request = request
    let revision = playManager.playbackRequestRevision
    let revisions = playManager.playbackRequests
    request.replacement = Task { [weak self, weak request] in
      for await changed in revisions {
        guard !Task.isCancelled, let self, let request, self.request === request else { return }
        if changed != revision && changed != request.playbackID {
          self.cancel()
          return
        }
      }
    }
    request.deadline = Task { [weak self, weak request, sleeper] in
      do { try await sleeper.sleep(for: .seconds(30)) } catch { return }
      guard !Task.isCancelled, let self, let request, self.request === request else { return }
      self.request = nil
      request.finish()
      Self.log.error("CarPlay selection timed out: episode=\(episodeID)")
      self.showError?("Playback is taking too long. Try again.")
    }
    request.work = Task { [weak self, weak request] in
      guard let self, let request else { return }
      defer {
        if self.request === request { self.request = nil }
        request.finish()
      }
      await appLauncher.prepareForPlayback()
      guard !Task.isCancelled, self.request === request else { return }
      do {
        let episode = try await repo.podcastEpisode(episodeID)
        guard !Task.isCancelled, self.request === request else { return }
        guard playManager.playbackRequestRevision == revision else { return }
        guard let episode else {
          Self.log.error("CarPlay selected episode no longer exists: episode=\(episodeID)")
          showError?("This episode is no longer available.")
          return
        }
        if sharedState.currentEpisodeID == episodeID {
          guard await playManager.settledOnDeckID == episodeID else {
            showError?("This episode is not ready. Try again.")
            return
          }
        } else {
          let outcome = try await playManager.play(
            episode,
            replacing: revision,
            requestID: request.playbackID
          )
          guard !Task.isCancelled, self.request === request else { return }
          switch outcome {
          case .superseded: return
          case .unavailable:
            showError?("Couldn't start this episode. Try again.")
            return
          case .ready: break
          }
        }
        guard !Task.isCancelled, self.request === request,
          await playManager.settledOnDeckID == episodeID
        else { return }
        guard sharedState.currentEpisodeID == episodeID,
          [revision, request.playbackID].contains(playManager.playbackRequestRevision)
        else { return }
        showNowPlaying?()
      } catch {
        Self.log.caughtError("CarPlay selection failed: episode=\(episodeID)", error)
        guard !Task.isCancelled, self.request === request, !(error is CancellationError) else {
          return
        }
        guard [revision, request.playbackID].contains(playManager.playbackRequestRevision) else {
          return
        }
        showError?("Couldn't play this episode. Try again.")
      }
    }
  }

  func cancel() {
    let old = request
    request = nil
    old?.finish()
  }

  func disconnect() {
    connectionState = .disconnected
    cancel()
    showNowPlaying = nil
    showError = nil
  }
}
