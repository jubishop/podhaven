// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Logging

@MainActor protocol ManagingPodcasts: AnyObject {
  func queueLatestEpisodeToTop(_ podcastWithMetadata: PodcastWithEpisodeMetadata)
  func queueLatestEpisodeToBottom(_ podcastWithMetadata: PodcastWithEpisodeMetadata)
  func deletePodcast(_ podcastWithMetadata: PodcastWithEpisodeMetadata)
  func subscribePodcast(_ podcastWithMetadata: PodcastWithEpisodeMetadata)
  func unsubscribePodcast(_ podcastWithMetadata: PodcastWithEpisodeMetadata)

  func getOrCreatePodcast(_ podcastWithMetadata: PodcastWithEpisodeMetadata) async throws -> Podcast
}

extension ManagingPodcasts {
  private var repo: any Databasing { Container.shared.repo() }
  private var queue: any Queueing { Container.shared.queue() }
  private var alert: Alert { Container.shared.alert() }

  private var log: Logger { Log.as(LogSubsystem.ViewProtocols.managingPodcast) }

  func queueLatestEpisodeToTop(_ podcastWithMetadata: PodcastWithEpisodeMetadata) {
    Task { [weak self] in
      guard let self else { return }
      guard let podcastID = podcastWithMetadata.podcastID else { return }
      do {
        let latestEpisode = try await repo.latestEpisode(for: podcastID)
        if let latestEpisode = latestEpisode {
          try await queue.unshift(latestEpisode.id)
        }
      } catch {
        log.error(error)
      }
    }
  }

  func queueLatestEpisodeToBottom(_ podcastWithMetadata: PodcastWithEpisodeMetadata) {
    Task { [weak self] in
      guard let self else { return }
      guard let podcastID = podcastWithMetadata.podcastID else { return }
      do {
        let latestEpisode = try await repo.latestEpisode(for: podcastID)
        if let latestEpisode = latestEpisode {
          try await queue.append(latestEpisode.id)
        }
      } catch {
        log.error(error)
      }
    }
  }

  func deletePodcast(_ podcastWithMetadata: PodcastWithEpisodeMetadata) {
    Task { [weak self] in
      guard let self else { return }
      guard let podcastID = podcastWithMetadata.podcastID else { return }
      try await repo.delete(podcastID)
    }
  }

  func subscribePodcast(_ podcastWithMetadata: PodcastWithEpisodeMetadata) {
    Task { [weak self] in
      guard let self else { return }
      do {
        let podcast = try await getOrCreatePodcast(podcastWithMetadata)
        try await repo.markSubscribed(podcast.id)
      } catch {
        log.error(error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.coreMessage(for: error))
      }
    }
  }

  func unsubscribePodcast(_ podcastWithMetadata: PodcastWithEpisodeMetadata) {
    Task { [weak self] in
      guard let self else { return }
      guard let podcastID = podcastWithMetadata.podcastID else { return }
      try await repo.markUnsubscribed(podcastID)
    }
  }

  func getOrCreatePodcast(_ podcastWithMetadata: PodcastWithEpisodeMetadata) async throws -> Podcast
  {
    try await podcastWithMetadata.displayedPodcast.getOrCreatePodcast()
  }
}
