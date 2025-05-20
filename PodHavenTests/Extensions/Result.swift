// Copyright Justin Bishop, 2025

import Foundation

extension Result where Success: Equatable {
  var isFailure: Bool {
    if case .failure = self { return true }
    return false
  }

  func isSuccessfulWith(_ expectedData: Success) -> Bool {
    if case .success(let data) = self { return data == expectedData }
    return false
  }

  func isSuccessfulWith() -> Success? {
    if case .success(let data) = self { return data }
    return nil
  }

  func isSuccessful() -> Bool {
    if case .success = self { return true }
    return false
  }
}
