// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Logging

@MainActor protocol ManagingPodcasts: AnyObject {
  associatedtype PodcastType: PodcastListable

  func queueLatestEpisodeToTop(_ podcast: PodcastType)
  func queueLatestEpisodeToBottom(_ podcast: PodcastType)
  func deletePodcast(_ podcast: PodcastType)
  func subscribePodcast(_ podcast: PodcastType)
  func unsubscribePodcast(_ podcast: PodcastType)
  func addTag(_ tagID: Tag.ID, to podcast: PodcastType)
  func removeTag(_ tagID: Tag.ID, from podcast: PodcastType)

  func getOrCreatePodcast(_ podcast: PodcastType) async throws -> Podcast
}

extension ManagingPodcasts {
  private var repo: any Databasing { Container.shared.repo() }
  private var queue: any Queueing { Container.shared.queue() }
  private var alert: Alert { Container.shared.alert() }

  nonisolated private static var log: Logger { Log.as(LogSubsystem.ViewProtocols.managingPodcast) }

  // MARK: - Actions

  func queueLatestEpisodeToTop(_ podcast: PodcastType) {
    Task { [weak self] in
      guard let self else { return }

      do {
        let podcastID = try await getOrCreatePodcastID(podcast)
        let latestEpisode = try await repo.latestEpisode(for: podcastID)
        if let latestEpisode = latestEpisode {
          try await queue.unshift(latestEpisode.id)
        }
      } catch {
        Self.log.caughtError("queueLatestEpisodeToTop: failed for \(podcast.title)", error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
    }
  }

  func queueLatestEpisodeToBottom(_ podcast: PodcastType) {
    Task { [weak self] in
      guard let self else { return }

      do {
        let podcastID = try await getOrCreatePodcastID(podcast)
        let latestEpisode = try await repo.latestEpisode(for: podcastID)
        if let latestEpisode = latestEpisode {
          try await queue.append(latestEpisode.id)
        }
      } catch {
        Self.log.caughtError("queueLatestEpisodeToBottom: failed for \(podcast.title)", error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
    }
  }

  func deletePodcast(_ podcast: PodcastType) {
    guard let podcastID = podcast.podcastID else { return }

    Task { [weak self] in
      guard let self else { return }

      do {
        try await repo.deletePodcast(podcastID)
      } catch {
        Self.log.caughtError("deletePodcast: failed for podcast \(podcastID)", error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
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
        Self.log.caughtError("subscribePodcast: failed for \(podcast.title)", error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
    }
  }

  func unsubscribePodcast(_ podcast: PodcastType) {
    guard let podcastID = podcast.podcastID else { return }

    Task { [weak self] in
      guard let self else { return }

      do {
        try await repo.markUnsubscribed(podcastID)
      } catch {
        Self.log.caughtError("unsubscribePodcast: failed for podcast \(podcastID)", error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
    }
  }

  func addTag(_ tagID: Tag.ID, to podcast: PodcastType) {
    Task { [weak self] in
      guard let self else { return }

      do {
        let podcastID = try await getOrCreatePodcastID(podcast)
        try await repo.addTag(tagID, to: podcastID)
      } catch {
        Self.log.caughtError(
          "addTag: failed to add tag \(tagID) to podcast \(podcast.title)",
          error
        )
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
    }
  }

  func removeTag(_ tagID: Tag.ID, from podcast: PodcastType) {
    Task { [weak self] in
      guard let self else { return }

      do {
        let podcastID = try await getOrCreatePodcastID(podcast)
        _ = try await repo.removeTag(tagID, from: podcastID)
      } catch {
        Self.log.caughtError(
          "removeTag: failed to remove tag \(tagID) from podcast \(podcast.title)",
          error
        )
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
    }
  }

  // MARK: - Helpers

  private func getOrCreatePodcastID(_ podcast: PodcastType) async throws -> Podcast.ID {
    try await getOrCreatePodcast(podcast).id
  }
}

extension ManagingPodcasts where PodcastType == Podcast {
  func getOrCreatePodcast(_ podcast: Podcast) async throws -> Podcast { podcast }
}
