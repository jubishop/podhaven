// Copyright Justin Bishop, 2025

import Foundation

enum ParseError: KittedError {
  case invalidData(data: Data, caught: Error)
  case caught(Error)

  var userFriendlyMessage: String {
    switch self {
    case .invalidData(let data, let error):
      return
        """
        Invalid data
          Data: \(String(decoding: data, as: UTF8.self))
          Caught: \(Self.nestedUserFriendlyMessage(for: error))
        """
    case .caught(let error):
      return nestedUserFriendlyCaughtMessage(error)
    }
  }
}
