// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Logging
import Tagged

extension Container {
  var widgetService: Factory<WidgetService> {
    Factory(self) { WidgetService() }.scope(.cached)
  }
}

struct WidgetService {
  @DynamicInjected(\.repo) private var repo

  private var navigation: Navigation { get async { await Container.shared.navigation() } }

  private static let log = Log.as(LogSubsystem.Widget.service)

  // MARK: - URL Analysis

  static func isWidgetURL(_ url: URL) -> Bool {
    url.host == "widget"
  }

  // MARK: - URL Handling

  func handleIncomingURL(_ url: URL) async {
    let navigation = await self.navigation
    let pathComponents = url.pathComponents.filter { $0 != "/" }

    switch pathComponents.first {
    case "now-playing":
      Self.log.debug("Widget deep link: now-playing")
      await navigation.showOnDeckEpisodeDetail()

    case "queue":
      if let idString = pathComponents.dropFirst().first,
        let episodeIDInt = Int64(idString)
      {
        let episodeID = Episode.ID(rawValue: episodeIDInt)
        Self.log.debug("Widget deep link: queue episode \(episodeID)")

        do {
          if let podcastEpisode = try await repo.podcastEpisode(episodeID) {
            await navigation.showEpisode(podcastEpisode)
          } else {
            Self.log.warning("Widget deep link: episode \(episodeID) not found")
            await navigation.showUpNext()
          }
        } catch {
          Self.log.caughtError(
            "Widget deep link: failed to fetch episode \(episodeID)",
            error
          )
          await navigation.showUpNext()
        }
      } else {
        await navigation.showUpNext()
      }

    case "podcast-detail":
      let subComponents = Array(pathComponents.dropFirst())

      if subComponents.first == "episode",
        let idString = subComponents.dropFirst().first,
        let episodeIDInt = Int64(idString)
      {
        let episodeID = Episode.ID(rawValue: episodeIDInt)
        Self.log.debug("Widget deep link: podcast-detail episode \(episodeID)")

        do {
          if let podcastEpisode = try await repo.podcastEpisode(episodeID) {
            await navigation.showEpisode(podcastEpisode)
          } else {
            Self.log.warning("Widget deep link: episode \(episodeID) not found")
          }
        } catch {
          Self.log.caughtError(
            "Widget deep link: failed to fetch episode \(episodeID)",
            error
          )
        }
      } else if let feedURLString = URLComponents(string: url.absoluteString)?
        .queryItems?
        .first(where: { $0.name == "feedURL" })?
        .value,
        let feedURL = URL(string: feedURLString)
      {
        let typedFeedURL = FeedURL(rawValue: feedURL)
        Self.log.debug("Widget deep link: podcast-detail podcast \(typedFeedURL)")

        do {
          if let podcast = try await repo.podcast(typedFeedURL) {
            await navigation.showPodcast(podcast)
          } else {
            Self.log.warning("Widget deep link: podcast \(typedFeedURL) not found")
          }
        } catch {
          Self.log.caughtError(
            "Widget deep link: failed to fetch podcast \(typedFeedURL)",
            error
          )
        }
      } else {
        Self.log.warning("Widget deep link: unrecognized podcast-detail URL: \(url)")
      }

    default:
      Self.log.warning("Unknown widget deep link path: \(url)")
    }
  }
}
