// Copyright Justin Bishop, 2025

import Foundation

struct ITunesTopPodcastsResponse: Decodable, Sendable {
  var iTunesIDs: [ITunesPodcastID] { feed.iTunesIDs }

  private struct Feed: Decodable, Sendable {
    var iTunesIDs: [ITunesPodcastID] {
      entries.compactMap(\.iTunesID)
    }

    private struct Entry: Decodable, Sendable {
      var iTunesID: ITunesPodcastID? {
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
