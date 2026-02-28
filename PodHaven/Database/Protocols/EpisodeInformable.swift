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

extension EpisodeInformable {
  var previouslyQueued: Bool { queueDate != nil }

  // MARK: - Searchable

  var searchableString: String { "\(title) - \(description ?? "")" }
}
