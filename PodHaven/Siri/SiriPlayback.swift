// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Intents
import Logging
import Tagged

extension Container {
  var siriAuthorized: Factory<@Sendable () -> Bool> {
    Factory(self) { { INPreferences.siriAuthorizationStatus() == .authorized } }
  }

  @MainActor var siriPlayback: Factory<SiriPlayback> {
    Factory(self) { SiriPlayback() }.scope(.cached)
  }
}

@MainActor
final class SiriPlayback {
  private final class Request {
    let playbackID = UUID()
    var completion: SiriMediaIntentHandler.Completion?
    var work: Task<Void, Never>?
    var deadline: Task<Void, Never>?
    var replacement: Task<Void, Never>?

    init(completion: @escaping SiriMediaIntentHandler.Completion) {
      self.completion = completion
    }

    func finish(_ code: INPlayMediaIntentResponseCode) {
      let callback = completion
      completion = nil
      work?.cancel()
      deadline?.cancel()
      replacement?.cancel()
      work = nil
      deadline = nil
      replacement = nil
      callback?(INPlayMediaIntentResponse(code: code, userActivity: nil))
    }
  }

  @DynamicInjected(\.appLauncher) private var appLauncher
  @DynamicInjected(\.playManager) private var playManager
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.sharedState) private var sharedState
  @DynamicInjected(\.sleeper) private var sleeper
  private static let log = Log.as("SiriPlayback")
  private var request: Request?
  private var presentation: (id: UUID, show: () -> Void)?

  lazy var handler = SiriMediaIntentHandler(
    catalog: { try Container.shared.siriCatalogFile().read() },
    authorized: { Container.shared.siriAuthorized()() },
    playback: { selection, completion in
      Task { @MainActor in
        Container.shared.siriPlayback().play(selection, completion: completion)
      }
    }
  )

  fileprivate init() {}

  func connectPresentation(id: UUID, show: @escaping () -> Void) {
    presentation = (id, show)
  }

  func disconnectPresentation(id: UUID) {
    if presentation?.id == id { presentation = nil }
  }

  private func play(
    _ selection: SiriMediaSelection,
    completion: @escaping SiriMediaIntentHandler.Completion
  ) {
    request?.finish(.failure)
    let request = Request(completion: completion)
    self.request = request
    let showNowPlaying = presentation?.show
    let revision = playManager.playbackRequestRevision
    let changes = playManager.playbackRequests
    request.replacement = Task { [weak self, weak request] in
      for await changed in changes {
        guard !Task.isCancelled, let self, let request, self.request === request else { return }
        if changed != revision && changed != request.playbackID {
          self.request = nil
          request.finish(.failure)
          return
        }
      }
    }
    request.deadline = Task { [weak self, weak request, sleeper] in
      do { try await sleeper.sleep(for: .seconds(30)) } catch { return }
      guard !Task.isCancelled, let self, let request, self.request === request else { return }
      self.request = nil
      Self.log.error("Siri playback timed out")
      request.finish(.failure)
    }
    request.work = Task { [weak self, weak request] in
      guard let self, let request else { return }
      defer {
        if self.request === request { self.request = nil }
        request.finish(.failure)
      }
      await appLauncher.prepareForPlayback()
      guard !Task.isCancelled, self.request === request else { return }
      do {
        let identity = selection.identity
        let episode: PodcastEpisode?
        switch identity.kind {
        case .episode:
          episode = try await repo.podcastEpisode(Episode.ID(identity.id))
          guard let episode,
            episode.feedURL.absoluteString == identity.feed,
            episode.episode.guid.rawValue == identity.guid,
            "\(episode.title) — \(episode.podcastTitle)" == selection.title
          else { return }
        case .podcast:
          let series = try await repo.podcastSeries(Podcast.ID(identity.id))
          guard let series,
            series.podcast.feedURL.absoluteString == identity.feed,
            series.podcast.title == selection.title
          else { return }
          let unfinished = series.episodes.filter { $0.finishDate == nil }
          let chosen =
            unfinished.first { $0.id == sharedState.currentEpisodeID }
            ?? unfinished.sorted {
              if $0.pubDate != $1.pubDate { return $0.pubDate > $1.pubDate }
              return $0.id.rawValue < $1.id.rawValue
            }
            .first
          guard let chosen else {
            request.finish(.failureNoUnplayedContent)
            return
          }
          episode = try await repo.podcastEpisode(chosen.id)
        }
        guard !Task.isCancelled, self.request === request,
          playManager.playbackRequestRevision == revision,
          Container.shared.siriAuthorized()(), let episode
        else { return }
        guard
          try Container.shared.siriCatalogFile().read().generation == selection.catalogGeneration
        else {
          Self.log.debug("Siri library changed before playback: media=\(selection.identity.id)")
          return
        }
        let outcome = try await playManager.play(
          episode,
          replacing: revision,
          requestID: request.playbackID
        )
        guard outcome == .ready, !Task.isCancelled, self.request === request else { return }
        let states = sharedState.$playbackStatus.stream()
        for await state in states {
          guard !Task.isCancelled, self.request === request,
            playManager.playbackRequestRevision == request.playbackID,
            sharedState.currentEpisodeID == episode.id
          else { return }
          if state.playing {
            guard await playManager.settledOnDeckID == episode.id,
              !Task.isCancelled, self.request === request,
              playManager.playbackRequestRevision == request.playbackID,
              sharedState.currentEpisodeID == episode.id
            else { return }
            showNowPlaying?()
            Self.log.info("Siri playback ready: episode=\(episode.id)")
            request.finish(.success)
            return
          }
          if state.stopped { return }
        }
      } catch {
        Self.log.caughtError("Siri playback failed: media=\(selection.identity.id)", error)
      }
    }
  }
}
