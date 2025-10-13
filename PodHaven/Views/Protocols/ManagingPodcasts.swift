// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Logging

@MainActor protocol ManagingPodcasts: AnyObject {
  func queueLatestEpisodeToTop(_ podcast: any PodcastDisplayable)
  func queueLatestEpisodeToBottom(_ podcast: any PodcastDisplayable)
  func deletePodcast(_ podcast: any PodcastDisplayable)
  func subscribePodcast(_ podcast: any PodcastDisplayable)
  func unsubscribePodcast(_ podcast: any PodcastDisplayable)

  func getOrCreatePodcast(_ podcast: any PodcastDisplayable) async throws -> Podcast
}

extension ManagingPodcasts {
  private var repo: any Databasing { Container.shared.repo() }
  private var queue: any Queueing { Container.shared.queue() }
  private var alert: Alert { Container.shared.alert() }

  private var log: Logger { Log.as(LogSubsystem.ViewProtocols.managingPodcast) }

  func queueLatestEpisodeToTop(_ podcast: any PodcastDisplayable) {
    Task { [weak self] in
      guard let self else { return }
      guard let podcastID = podcast.podcastID else { return }

      do {
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

  func queueLatestEpisodeToBottom(_ podcast: any PodcastDisplayable) {
    Task { [weak self] in
      guard let self else { return }
      guard let podcastID = podcast.podcastID else { return }

      do {
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

  func deletePodcast(_ podcast: any PodcastDisplayable) {
    Task { [weak self] in
      guard let self else { return }
      guard let podcastID = podcast.podcastID else { return }

      do {
        try await repo.delete(podcastID)
      } catch {
        log.error(error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.coreMessage(for: error))
      }
    }
  }

  func subscribePodcast(_ podcast: any PodcastDisplayable) {
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

  func unsubscribePodcast(_ podcast: any PodcastDisplayable) {
    Task { [weak self] in
      guard let self else { return }
      guard let podcastID = podcast.podcastID else { return }

      do {
        try await repo.markUnsubscribed(podcastID)
      } catch {
        log.error(error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.coreMessage(for: error))
      }
    }
  }

  func getOrCreatePodcast(_ podcast: any PodcastDisplayable) async throws -> Podcast {
    try await DisplayedPodcast.getOrCreatePodcast(podcast)
  }
}
