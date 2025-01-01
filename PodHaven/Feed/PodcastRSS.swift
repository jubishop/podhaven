// Copyright Justin Bishop, 2025

import Foundation
import XMLCoder

struct PodcastRSS: Codable, Sendable {
  // MARK: - Static Parsing Methods

  static func parse(_ url: URL) async throws -> Podcast {
    let data = try Data(contentsOf: url)
    return try await parse(data)
  }

  static func parse(_ data: Data) async throws -> Podcast {
    try await withCheckedThrowingContinuation { continuation in
      do {
        let podcastRSS = try XMLDecoder().decode(PodcastRSS.self, from: data)
        continuation.resume(returning: podcastRSS.channel)
      } catch {
        continuation.resume(throwing: error)
      }
    }
  }

  // MARK: - Models

  struct Podcast: Codable, Sendable {
    let title: String

    var episodes: [Episode] { item }
    private let item: [Episode]
  }

  struct Episode: Codable, Sendable {
    let title: String
  }

  // MARK: - Private

  private let channel: Podcast
}
