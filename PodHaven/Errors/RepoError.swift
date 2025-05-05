// Copyright Justin Bishop, 2025

import ErrorKit
import Foundation

enum RepoError: KittedError {
  case insertFailure(description: String, caught: Error)
  case readFailure(type: Any.Type, id: Int64, caught: Error)
  case updateFailure(type: Any.Type, id: Int64, caught: Error)
  case caught(Error)

  var userFriendlyMessage: String {
    switch self {
    case .insertFailure(let description, let error):
      return
        """
        Failed to insert record.
          Description: \(description)
        Caught ->
          \(Self.nestedUserFriendlyMessage(for: error))
        """
    case .readFailure(let type, let id, let error):
      return
        """
        Failed to read record.
          Type: \(String(describing: type))
          ID: \(id)
        Caught ->
          \(Self.nestedUserFriendlyMessage(for: error))
        """
    case .updateFailure(let type, let id, let error):
      return
        """
        Failed to update record.
          Type: \(String(describing: type))
          ID: \(id)
        Caught ->
          \(Self.nestedUserFriendlyMessage(for: error))
        """
    case .caught(let error):
      return nestedUserFriendlyCaughtMessage(error)
    }
  }
}
