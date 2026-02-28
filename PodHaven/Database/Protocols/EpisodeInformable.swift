// Copyright Justin Bishop, 2025

import Foundation

protocol EpisodeInformable:
  EpisodeFoundational,
  Searchable
{
  // MARK: - Core Properties

  var description: String? { get }

  // MARK: - User Properties

  var queueDate: Date? { get }
  var previouslyQueued: Bool { get }
}

// MARK: - Default Implementations

private let timestampNewlineRegex: NSRegularExpression = {
  guard
    let regex = try? NSRegularExpression(
      pattern: #"(?<=.)(?<!\n)(?<!\d)(\d{1,2}:\d{2}(?::\d{2})?)(?![\d:])"#
    )
  else {
    Assert.fatal("timestampNewlineRegex pattern is invalid")
  }
  return regex
}()

extension EpisodeInformable {
  var previouslyQueued: Bool { queueDate != nil }

  // MARK: - Searchable

  var searchableString: String { "\(title) - \(description ?? "")" }

  // MARK: - Timestamp Formatting

  // Description with newlines inserted before timestamps that don't already have one,
  // so chapter listings display as separate lines.
  var descriptionWithNewlines: String? {
    guard let description else { return nil }
    return timestampNewlineRegex.stringByReplacingMatches(
      in: description,
      range: NSRange(description.startIndex..<description.endIndex, in: description),
      withTemplate: "\n$1"
    )
  }
}
