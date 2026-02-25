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
  @DynamicInjected(\.navigation) private var navigation
  @DynamicInjected(\.repo) private var repo

  private static let log = Log.as(LogSubsystem.Widget.service)

  // MARK: - URL Analysis

  static func isWidgetURL(_ url: URL) -> Bool {
    url.host == "widget"
  }

  // MARK: - URL Handling

  func handleIncomingURL(_ url: URL) async {
    let pathComponents = url.pathComponents.filter { $0 != "/" }

    switch pathComponents.first {
    case "now-playing":
      Self.log.debug("Widget deep link: now-playing")
      navigation.currentTab = .upNext

    case "queue":
      if let idString = pathComponents.dropFirst().first,
        let episodeIDInt = Int64(idString)
      {
        let episodeID = Episode.ID(rawValue: episodeIDInt)
        Self.log.debug("Widget deep link: queue episode \(episodeID)")

        do {
          if let podcastEpisode = try await repo.podcastEpisode(episodeID) {
            navigation.showEpisode(podcastEpisode)
          } else {
            Self.log.warning("Widget deep link: episode \(episodeID) not found")
            navigation.currentTab = .upNext
          }
        } catch {
          Self.log.error(error)
          navigation.currentTab = .upNext
        }
      } else {
        navigation.currentTab = .upNext
      }

    default:
      Self.log.warning("Unknown widget deep link path: \(url)")
    }
  }
}
