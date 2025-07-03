// Copyright Justin Bishop, 2025

import Foundation
import XMLCoder

struct PodcastOPML: Decodable, Sendable {
  // MARK: - Static Parsing Methods

  static func parse(_ url: URL) async throws -> PodcastOPML {
    let data = try await URLSession.shared.validatedData(from: url)
    return try await parse(data)
  }

  static func parse(_ data: Data) async throws(ParseError) -> PodcastOPML {
    do {
      return try await withCheckedThrowingContinuation { continuation in
        do {
          let decoder = XMLDecoder()
          let podcastOPML = try decoder.decode(PodcastOPML.self, from: data)
          continuation.resume(returning: podcastOPML)
        } catch let error {
          continuation.resume(throwing: error)
        }
      }
    } catch {
      throw ParseError.invalidData(data: data, caught: error)
    }
  }

  // MARK: - Models

  struct Body: Decodable, Sendable {
    struct Outline: Decodable, Sendable {
      let text: String
      let xmlUrl: FeedURL
    }
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
