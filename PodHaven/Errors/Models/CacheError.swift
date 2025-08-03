// Copyright Justin Bishop, 2025

import Foundation
import ReadableErrorMacro

@ReadableError
enum CacheError: ReadableError, CatchingError {
  case episodeNotFound(Episode.ID)
  case documentsDirectoryNotFound
  case caught(Error)

  var message: String {
    switch self {
    case .episodeNotFound(let episodeID):
      return "Episode \(episodeID) not found for cache operation"
    case .documentsDirectoryNotFound:
      return "Documents directory not found for cache storage"
    case .caught: return ""
    }
  }
}
