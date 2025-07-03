// Copyright Justin Bishop, 2025

import Foundation

@testable import PodHaven

extension DownloadData {
  init(url: URL) {
    self.init(url: url, data: url.dataRepresentation)
  }
}
