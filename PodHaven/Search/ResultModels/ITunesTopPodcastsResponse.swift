// Copyright Justin Bishop, 2025

import Foundation

struct ITunesTopPodcastsResponse: Decodable, Sendable {
  let feed: Feed

  struct Feed: Decodable, Sendable {
    let entries: [Entry]

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

  struct Entry: Decodable, Sendable {
    let id: Identifier

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
}
