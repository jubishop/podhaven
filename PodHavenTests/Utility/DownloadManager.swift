// Copyright Justin Bishop, 2024 

import Foundation

@testable import PodHaven

extension DownloadData {
  init(url: URL) {
    self.init(url: url, data: url.dataRepresentation)
  }
}

extension DownloadResult {
  var isCancelled: Bool {
    if case .failure(.cancelled) = self {
      return true
    }
    return false
  }

  func isSuccessfulWith(_ expectedData: DownloadData) -> Bool {
    if case .success(let downloadData) = self {
      return downloadData == expectedData
    }
    return false
  }

  func isSuccessful() -> Bool {
    if case .success = self {
      return true
    }
    return false
  }
}
