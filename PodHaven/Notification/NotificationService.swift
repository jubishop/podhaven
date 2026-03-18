// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Logging
import Tagged

extension Container {
  var notificationService: Factory<NotificationService> {
    Factory(self) { NotificationService() }.scope(.cached)
  }
}

struct NotificationService {
  @DynamicInjected(\.repo) private var repo

  private var navigation: Navigation { get async { await Container.shared.navigation() } }

  private static let log = Log.as(LogSubsystem.NotificationService.main)

  // MARK: - URL Analysis

  static func isNotificationURL(_ url: URL) -> Bool {
    url.host == "notification"
  }

  // MARK: - URL Construction

  static func episodeURL(_ episodeID: Episode.ID) -> String {
    "podhaven://notification/episode/\(episodeID.rawValue)"
  }

  static func podcastURL(_ podcastID: Podcast.ID) -> String {
    "podhaven://notification/podcast/\(podcastID.rawValue)"
  }

  // MARK: - URL Handling

  func handleIncomingURL(_ url: URL) async {
    let pathComponents = url.pathComponents.filter { $0 != "/" }

    switch pathComponents.first {
    case "episode":
      if let idString = pathComponents.dropFirst().first,
        let episodeIDInt = Int64(idString)
      {
        let episodeID = Episode.ID(rawValue: episodeIDInt)
        Self.log.debug("Notification deep link: episode \(episodeID)")

        do {
          if let podcastEpisode = try await repo.podcastEpisode(episodeID) {
            await navigation.showEpisode(podcastEpisode)
          } else {
            Self.log.warning("Notification deep link: episode \(episodeID) not found")
            await navigation.showPodcastList(.subscribed)
          }
        } catch {
          Self.log.caughtError(
            "Notification deep link: failed to fetch episode \(episodeID)",
            error
          )
          await navigation.showPodcastList(.subscribed)
        }
      }

    case "podcast":
      if let idString = pathComponents.dropFirst().first,
        let podcastIDInt = Int64(idString)
      {
        let podcastID = Podcast.ID(rawValue: podcastIDInt)
        Self.log.debug("Notification deep link: podcast \(podcastID)")

        do {
          if let podcastSeries = try await repo.podcastSeries(podcastID) {
            await navigation.showPodcast(podcastSeries.podcast)
          } else {
            Self.log.warning("Notification deep link: podcast \(podcastID) not found")
            await navigation.showPodcastList(.subscribed)
          }
        } catch {
          Self.log.caughtError(
            "Notification deep link: failed to fetch podcast \(podcastID)",
            error
          )
          await navigation.showPodcastList(.subscribed)
        }
      }

    default:
      Self.log.warning("Unknown notification deep link path: \(url)")
    }
  }
}
