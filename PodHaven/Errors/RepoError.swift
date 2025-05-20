// Copyright Justin Bishop, 2025

import Foundation
import GRDB
import ReadableErrorMacro

@ReadableError
enum RepoError: ReadableError {
  case insertFailure(description: String, caught: Error)
  case readAllFailure(type: any FetchableRecord.Type, filter: SQLExpression, caught: Error)
  case readFailure(type: any FetchableRecord.Type, id: Int64, caught: Error)
  case updateFailure(type: any FetchableRecord.Type, id: Int64, description: String, caught: Error)

  var message: String {
    switch self {
    case .insertFailure(let description, _):
      return
        """
        Failed to insert record
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
    case .updateFailure(let type, let description, let id, _):
      return
        """
        Failed to update record
          Type: \(String(describing: type))
          ID: \(id)
          Description: \(description)
        """
    }
  }
}
