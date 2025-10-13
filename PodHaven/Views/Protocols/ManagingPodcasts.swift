// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Logging

@MainActor protocol ManagingPodcasts: AnyObject {
  associatedtype PodcastType: PodcastDisplayable

  func queueLatestEpisodeToTop(_ podcast: PodcastType)
  func queueLatestEpisodeToBottom(_ podcast: PodcastType)
  func deletePodcast(_ podcast: PodcastType)
  func subscribePodcast(_ podcast: PodcastType)
  func unsubscribePodcast(_ podcast: PodcastType)

  func getOrCreatePodcast(_ podcast: PodcastType) async throws -> Podcast
}

extension ManagingPodcasts {
  private var repo: any Databasing { Container.shared.repo() }
  private var queue: any Queueing { Container.shared.queue() }
  private var alert: Alert { Container.shared.alert() }

  private var log: Logger { Log.as(LogSubsystem.ViewProtocols.managingPodcast) }

  func queueLatestEpisodeToTop(_ podcast: PodcastType) {
    Task { [weak self] in
      guard let self else { return }

      do {
        let podcastID = try await getPodcastID(podcast)
        let latestEpisode = try await repo.latestEpisode(for: podcastID)
        if let latestEpisode = latestEpisode {
          try await queue.unshift(latestEpisode.id)
        }
      } catch {
        log.error(error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.coreMessage(for: error))
      }
    }
  }

  func queueLatestEpisodeToBottom(_ podcast: PodcastType) {
    Task { [weak self] in
      guard let self else { return }

      do {
        let podcastID = try await getPodcastID(podcast)
        let latestEpisode = try await repo.latestEpisode(for: podcastID)
        if let latestEpisode = latestEpisode {
          try await queue.append(latestEpisode.id)
        }
      } catch {
        log.error(error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.coreMessage(for: error))
      }
    }
  }

  func deletePodcast(_ podcast: PodcastType) {
    Task { [weak self] in
      guard let self else { return }

      do {
        let podcastID = try await getPodcastID(podcast)
        try await repo.delete(podcastID)
      } catch {
        log.error(error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.coreMessage(for: error))
      }
    }
  }

  func subscribePodcast(_ podcast: PodcastType) {
    Task { [weak self] in
      guard let self else { return }

      do {
        let podcast = try await getOrCreatePodcast(podcast)
        try await repo.markSubscribed(podcast.id)
      } catch {
        log.error(error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.coreMessage(for: error))
      }
    }
  }

  func unsubscribePodcast(_ podcast: PodcastType) {
    Task { [weak self] in
      guard let self else { return }

      do {
        let podcastID = try await getPodcastID(podcast)
        try await repo.markUnsubscribed(podcastID)
      } catch {
        log.error(error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.coreMessage(for: error))
      }
    }
  }

  // MARK: - Helpers

  private func getPodcastID(_ podcast: PodcastType) async throws -> Podcast.ID {
    try await getOrCreatePodcast(podcast).id
  }
}

extension ManagingPodcasts where PodcastType == Podcast {
  func getOrCreatePodcast(_ podcast: Podcast) async throws -> Podcast { podcast }
}
