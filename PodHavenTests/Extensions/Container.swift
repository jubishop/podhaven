// Copyright Justin Bishop, 2025

import Factory
import Foundation

@testable import PodHaven

extension Container: @retroactive AutoRegistering {
  public func autoRegister() {
    repo.context(.test) { Repo.inMemory() }.scope(.unique)
  }
}
