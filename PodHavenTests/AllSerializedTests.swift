// Copyright Justin Bishop, 2025

import Foundation
import Testing

@testable import PodHaven

@Suite(.serialized)
actor AllSerializedTests {
  @Suite class PlayManager: PlayManagerTests {}
}
