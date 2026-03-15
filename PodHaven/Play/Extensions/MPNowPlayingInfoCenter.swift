// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import MediaPlayer

extension Container {
  var mpNowPlayingInfoCenter: Factory<any MPNowPlayingInfoCenterable> {
    Factory(self) { MPNowPlayingInfoCenter.default() }
  }
}

extension MPNowPlayingInfoCenter: MPNowPlayingInfoCenterable {}
