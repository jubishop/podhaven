// Copyright Justin Bishop, 2025

import Foundation

extension TimeInterval {
  var readableFormat: String {
    let hours = Int(self) / 3600
    let minutes = (Int(self) % 3600) / 60
    let seconds = Int(self) % 60
    
    if hours > 0 {
      return "\(hours)h \(minutes)m"
    } else if minutes > 0 {
      return "\(minutes)m \(seconds)s"
    } else {
      return "\(seconds)s"
    }
  }
}