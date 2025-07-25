// Copyright Justin Bishop, 2025

import Foundation

protocol CommandableCenter: Sendable {
  var stream: AsyncStream<CommandCenter.Command> { get }
  func disableSeekCommands()
  func enableSeekCommands()
}
