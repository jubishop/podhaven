// Copyright Justin Bishop, 2026

import AppIntents
import Foundation

// MARK: - Entity

struct PodcastEntity: AppEntity {
  static let typeDisplayRepresentation: TypeDisplayRepresentation = "Podcast"
  static let defaultQuery = PodcastEntityQuery()

  let id: String
  let title: String

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(title)")
  }
}

// MARK: - Query

struct PodcastEntityQuery: EntityStringQuery {
  func entities(for identifiers: [String]) async throws -> [PodcastEntity] {
    let all = loadEntities()
    return all.filter { identifiers.contains($0.id) }
  }

  func entities(matching string: String) async throws -> [PodcastEntity] {
    let all = loadEntities()
    guard !string.isEmpty else { return all }
    return all.filter { $0.title.localizedCaseInsensitiveContains(string) }
  }

  func suggestedEntities() async throws -> [PodcastEntity] {
    loadEntities()
  }

  private func loadEntities() -> [PodcastEntity] {
    let url = WidgetInfo.podcastEntityListURL

    guard FileManager.default.fileExists(atPath: url.path) else { return [] }
    guard let data = try? Data(contentsOf: url) else { return [] }
    guard let snapshot = try? JSONDecoder().decode(PodcastEntityListSnapshot.self, from: data)
    else {
      return []
    }

    return snapshot.podcasts.map { item in
      PodcastEntity(id: item.feedURLString, title: item.title)
    }
  }
}

// MARK: - Configuration Intent

struct SelectPodcastIntent: WidgetConfigurationIntent {
  static let title: LocalizedStringResource = "Select Podcast"
  static let description: IntentDescription = "Choose a podcast to display on your home screen."

  @Parameter(title: "Podcast")
  var podcast: PodcastEntity?
}
