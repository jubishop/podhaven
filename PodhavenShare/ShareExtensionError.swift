// Copyright Justin Bishop, 2025

import Foundation

enum ShareExtensionError: Error, LocalizedError {
  case invalidURLScheme
  case noInputItems
  case noURLFound
  case urlLoadingFailed(any Error)
  case itemNotURL

  var errorDescription: String? {
    switch self {
    case .invalidURLScheme:
      return "Failed to create PodHaven URL scheme"
    case .noInputItems:
      return "No input items found in extension context"
    case .noURLFound:
      return "No URL found in shared content"
    case .urlLoadingFailed(let error):
      return "Failed to load URL: \(error)"
    case .itemNotURL:
      return "Shared item is not a URL"
    }
  }
}
