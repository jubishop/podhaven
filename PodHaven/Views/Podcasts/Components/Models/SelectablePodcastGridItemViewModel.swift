// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Logging
import SwiftUI

typealias SelectablePodcastGridItemViewModel = SelectableListItemModel<Podcast>

extension SelectablePodcastGridItemViewModel {
  private var queue: any Queueing { Container.shared.queue() }
  private var repo: Databasing { Container.shared.repo() }

  private var log: Logger { Log.as(LogSubsystem.PodcastsView.podcastGrid) }

  func queueLatestEpisodeToTop() {
    Task { [weak self] in
      guard let self else { return }
      do {
        let latestEpisode = try await repo.latestEpisode(for: item.id)
        if let latestEpisode = latestEpisode {
          try await queue.unshift(latestEpisode.id)
        }
      } catch {
        log.error(error)
      }
    }
  }

  func queueLatestEpisodeToBottom() {
    Task { [weak self] in
      guard let self else { return }
      do {
        let latestEpisode = try await repo.latestEpisode(for: item.id)
        if let latestEpisode = latestEpisode {
          try await queue.append(latestEpisode.id)
        }
      } catch {
        log.error(error)
      }
    }
  }

  func deletePodcast() {
    Task { [weak self] in
      guard let self else { return }
      try await repo.delete(item.id)
    }
  }

  func subscribePodcast() {
    Task { [weak self] in
      guard let self else { return }
      try await repo.markSubscribed(item.id)
    }
  }

  func unsubscribePodcast() {
    Task { [weak self] in
      guard let self else { return }
      try await repo.markUnsubscribed(item.id)
    }
  }
}
