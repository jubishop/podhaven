// Copyright Justin Bishop, 2025

import Foundation
import ReadableErrorMacro

@ReadableError
enum PermissionError: ReadableError {
  case securityScopedResourceDenied

  var message: String {
    switch self {
    case .securityScopedResourceDenied:
      return "Denied SecurityScopedResource"
    }
  }
}
