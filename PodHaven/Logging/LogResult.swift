// Copyright Justin Bishop, 2025

import Foundation
import Logging

enum LogResult: Sendable {
  case success
  case log(Logger.Level, @autoclosure @Sendable () -> Logger.Message)
  case failure(any Error)
}
