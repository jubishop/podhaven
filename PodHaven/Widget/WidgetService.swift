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
      let subpath = pathComponents.dropFirst().first
      if subpath == "episode" {
        Self.log.debug("Widget deep link: now-playing episode detail")
        await navigation.showOnDeckEpisodeDetail()
      } else {
        Self.log.debug("Widget deep link: now-playing play bar sheet")
        await navigation.showPlayBarSheet()
      }

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

    default:
      Self.log.warning("Unknown widget deep link path: \(url)")
    }
  }
}
