// Copyright Justin Bishop, 2025

import Foundation
import XMLCoder

struct PodcastOPML: Decodable, Sendable {
  // MARK: - Static Parsing Methods

  static func parse(_ url: URL) async throws -> PodcastOPML {
    let data = try Data(contentsOf: url)
    return try await parse(data)
  }

  static func parse(_ data: Data) async throws -> PodcastOPML {
    try await withCheckedThrowingContinuation { continuation in
      do {
        let decoder = XMLDecoder()
        let podcastOPML = try decoder.decode(PodcastOPML.self, from: data)
        continuation.resume(returning: podcastOPML)
      } catch {
        continuation.resume(throwing: error)
      }
    }
  }

  // MARK: - Models

  struct Outline: Decodable, Sendable {
    let text: String
    let xmlUrl: String
  }

  struct Body: Decodable, Sendable {
    let outlines: [Outline]

    enum CodingKeys: String, CodingKey {
      case outlines = "outline"
    }
  }
  let body: Body

  struct Head: Decodable, Sendable {
    let title: String?
  }
  let head: Head
}
