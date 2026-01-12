// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import MediaPlayer

extension Container {
  var mpRemoteCommandCenter: Factory<any MPRemoteCommandableCenter> {
    Factory(self) { MPRemoteCommandCenter.shared() }.scope(.cached)
  }
}

extension MPRemoteCommandEvent: MPRemoteCommandEventable {}

extension MPSkipIntervalCommandEvent: MPSkipIntervalCommandEventable {}

extension MPChangePlaybackPositionCommandEvent: MPChangePlaybackPositionCommandEventable {}

extension MPChangePlaybackRateCommandEvent: MPChangePlaybackRateCommandEventable {}

extension MPRemoteCommand: MPRemoteCommandable {
  func addCommandTarget(
    handler: @escaping (any MPRemoteCommandEventable) -> MPRemoteCommandHandlerStatus
  ) {
    addTarget { event in  // Calls the real MPRemoteCommand.addTarget
      handler(event)
    }
  }

  func removeCommandTarget() {
    removeTarget(nil)  // Calls the real MPRemoteCommand.removeTarget
  }
}

extension MPSkipIntervalCommand: MPSkipCommandable {}

extension MPChangePlaybackRateCommand: MPChangePlaybackRateCommandable {}

extension MPRemoteCommandCenter: MPRemoteCommandableCenter {
  var play: any MPRemoteCommandable { playCommand }
  var pause: any MPRemoteCommandable { pauseCommand }
  var togglePlayPause: any MPRemoteCommandable { togglePlayPauseCommand }
  var skipForward: any MPSkipCommandable { skipForwardCommand }
  var skipBackward: any MPSkipCommandable { skipBackwardCommand }
  var changePlaybackPosition: any MPRemoteCommandable { changePlaybackPositionCommand }
  var nextTrack: any MPRemoteCommandable { nextTrackCommand }
  var previousTrack: any MPRemoteCommandable { previousTrackCommand }
  var changePlaybackRate: any MPChangePlaybackRateCommandable { changePlaybackRateCommand }
  var like: any MPRemoteCommandable { likeCommand }
  var dislike: any MPRemoteCommandable { dislikeCommand }
  var bookmark: any MPRemoteCommandable { bookmarkCommand }
  var rating: any MPRemoteCommandable { ratingCommand }
}
