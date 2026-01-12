// Copyright Justin Bishop, 2025

import Foundation
import MediaPlayer

protocol MPRemoteCommandEventable {}

protocol MPSkipIntervalCommandEventable: MPRemoteCommandEventable {
  var interval: TimeInterval { get }
}

protocol MPChangePlaybackPositionCommandEventable: MPRemoteCommandEventable {
  var positionTime: TimeInterval { get }
}

protocol MPChangePlaybackRateCommandEventable: MPRemoteCommandEventable {
  var playbackRate: Float { get }
}

protocol MPRemoteCommandable: AnyObject {
  func addCommandTarget(
    handler: @escaping (any MPRemoteCommandEventable) -> MPRemoteCommandHandlerStatus
  )
  func removeCommandTarget()
  var isEnabled: Bool { get set }
}

protocol MPSkipCommandable: MPRemoteCommandable {
  var preferredIntervals: [NSNumber] { get set }
}

protocol MPChangePlaybackRateCommandable: MPRemoteCommandable {
  var supportedPlaybackRates: [NSNumber] { get set }
}

protocol MPRemoteCommandableCenter {
  var play: any MPRemoteCommandable { get }
  var pause: any MPRemoteCommandable { get }
  var togglePlayPause: any MPRemoteCommandable { get }
  var skipForward: any MPSkipCommandable { get }
  var skipBackward: any MPSkipCommandable { get }
  var changePlaybackPosition: any MPRemoteCommandable { get }
  var nextTrack: any MPRemoteCommandable { get }
  var previousTrack: any MPRemoteCommandable { get }
  var changePlaybackRate: any MPChangePlaybackRateCommandable { get }
  var like: any MPRemoteCommandable { get }
  var dislike: any MPRemoteCommandable { get }
  var bookmark: any MPRemoteCommandable { get }
  var rating: any MPRemoteCommandable { get }
}
