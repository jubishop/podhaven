// Copyright Justin Bishop, 2025

import Foundation

struct ITunesTopPodcastsFeed: Decodable, Sendable {
  var podcastIDs: [ITunesPodcastID] { feed.podcastIDs }

  private struct Feed: Decodable, Sendable {
    var podcastIDs: [ITunesPodcastID] {
      entries.compactMap(\.podcastID)
    }

    private struct Entry: Decodable, Sendable {
      var podcastID: ITunesPodcastID? {
        guard let id = Int(id.attributes.imId)
        else { return nil }

        return ITunesPodcastID(rawValue: id)
      }

      private let id: Identifier

      struct Identifier: Decodable, Sendable {
        let attributes: Attributes

        struct Attributes: Decodable, Sendable {
          let imId: String

          private enum CodingKeys: String, CodingKey {
            case imId = "im:id"
          }
        }
      }
    }

    private let entries: [Entry]

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)

      if let multiple = try? container.decode([Entry].self, forKey: .entries) {
        entries = multiple
      } else if let single = try? container.decode(Entry.self, forKey: .entries) {
        entries = [single]
      } else {
        entries = []
      }
    }

    private enum CodingKeys: String, CodingKey {
      case entries = "entry"
    }
  }

  private let feed: Feed
}
