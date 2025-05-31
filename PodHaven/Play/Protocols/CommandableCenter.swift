// Copyright Justin Bishop, 2025 

import Foundation

protocol CommandableCenter {
  var stream: AsyncStream<CommandCenter.Command> { get }
}
