// Copyright Justin Bishop, 2025

import Foundation

enum ShareExtensionError: Error, LocalizedError {
  case applicationNotFound
  case invalidURLScheme
  case noInputItems
  case noURLFound
  case urlLoadingFailed(Error)
  case itemNotURL
  case sharedContainerNotFound

  var errorDescription: String? {
    switch self {
    case .applicationNotFound:
      return "UIApplication not found in responder chain"
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
    case .sharedContainerNotFound:
      return "Shared app group container not found"
    }
  }
}
