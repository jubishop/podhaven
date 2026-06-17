// Copyright Justin Bishop, 2025

import Foundation

enum Timestamp {
  // Regex<Substring> isn't Sendable-annotated upstream, but its compiled NFA is
  // immutable and matching is thread-safe. Precompile once to avoid recompiling
  // on every access (hot in RSS ingest and embedding background passes).
  nonisolated(unsafe) static let regex: Regex<Substring> =
    #/(?:\d{1,2}:\d{2}:\d{2}|\d{1,2}:\d{2})(?![\d:])/#

  // Parses a timestamp string (e.g. "2:15", "14:30", "1:02:15") into total seconds.
  static func parse(_ timestamp: some StringProtocol) -> Int? {
    let components = timestamp.split(separator: ":")

    guard components.count >= 2, components.count <= 3 else { return nil }

    guard components.count == 3 else {
      guard let minutes = Int(components[0]),
        let seconds = Int(components[1])
      else { return nil }
      return minutes * 60 + seconds
    }

    guard let hours = Int(components[0]),
      let minutes = Int(components[1]),
      let seconds = Int(components[2])
    else { return nil }

    return hours * 3600 + minutes * 60 + seconds
  }

  // Custom scheme carrying a raw timestamp so a description's tappable
  // timestamp can round-trip through a SwiftUI `Text` link into the episode
  // detail view's openURL handler, kept distinct from real http(s) links.
  private static let urlScheme = "podhaven-timestamp"

  static func url(for timestamp: some StringProtocol) -> URL? {
    var components = URLComponents()
    components.scheme = urlScheme
    components.host = "play"
    components.queryItems = [URLQueryItem(name: "t", value: String(timestamp))]
    return components.url
  }

  static func timestamp(fromURL url: URL) -> String? {
    guard url.scheme == urlScheme else { return nil }
    return URLComponents(url: url, resolvingAgainstBaseURL: false)?
      .queryItems?
      .first { $0.name == "t" }?
      .value
  }

  // Formats a timestamp string without unnecessary leading zeros.
  // Examples: "00:08:23" → "8:23", "0:40" → "0:40", "1:05:30" → "1:05:30"
  static func format(_ timestamp: some StringProtocol) -> String {
    func padded(_ value: Int) -> String {
      value < 10 ? "0\(value)" : "\(value)"
    }

    guard let totalSeconds = parse(timestamp) else {
      return String(timestamp)
    }

    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60

    guard hours > 0 else {
      return "\(minutes):\(padded(seconds))"
    }
    return "\(hours):\(padded(minutes)):\(padded(seconds))"
  }
}
