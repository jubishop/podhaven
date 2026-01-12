// Copyright Justin Bishop, 2025

import Foundation
import GRDB
import ReadableErrorMacro

@ReadableError
enum RepoError: ReadableError {
  case duplicateConflict(unsavedPodcastSeries: UnsavedPodcastSeries, caught: any Error)
  case insertFailure(type: any (Decodable & Sendable).Type, description: String, caught: any Error)
  case readAllFailure(
    type: any (Decodable & Sendable).Type,
    filter: SQLExpression,
    caught: any Error
  )
  case readFailure(type: any (Decodable & Sendable).Type, id: Int64, caught: any Error)
  case updateFailure(
    type: any (Decodable & Sendable).Type,
    id: Int64,
    description: String,
    caught: any Error
  )
  case upsertFailure(type: any (Decodable & Sendable).Type, description: String, caught: any Error)

  var message: String {
    switch self {
    case .duplicateConflict(let unsavedPodcastSeries, _):
      return
        """
        This feed or its episodes already exist in another subscription.
          Series: \(unsavedPodcastSeries.toString)
        """
    case .insertFailure(let type, let description, _):
      return
        """
        Failed to insert record
          Type: \(String(describing: type))
          Description: \(description)
        """
    case .readAllFailure(let type, let filter, _):
      return
        """
        Failed to fetch multiple records
          Type: \(String(describing: type))
          Filter: \(filter)
        """
    case .readFailure(let type, let id, _):
      return
        """
        Failed to read record
          Type: \(String(describing: type))
          ID: \(id)
        """
    case .updateFailure(let type, let id, let description, _):
      return
        """
        Failed to update record
          Type: \(String(describing: type))
          ID: \(id)
          Description: \(description)
        """
    case .upsertFailure(let type, let description, _):
      return
        """
        Failed to upsert record
          Type: \(String(describing: type))
          Description: \(description)
        """
    }
  }
}
