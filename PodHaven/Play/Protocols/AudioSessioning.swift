// Copyright Justin Bishop, 2026

import AVFoundation

protocol AudioSessioning: Sendable {
  var category: AVAudioSession.Category { get }
  var mode: AVAudioSession.Mode { get }
  var routeSharingPolicy: AVAudioSession.RouteSharingPolicy { get }
  var isOtherAudioPlaying: Bool { get }
  var currentRouteOutputs: [AVAudioSession.Port] { get }

  func setCategory(
    _ category: AVAudioSession.Category,
    mode: AVAudioSession.Mode,
    policy: AVAudioSession.RouteSharingPolicy,
    options: AVAudioSession.CategoryOptions
  ) throws
  func setMode(_ mode: AVAudioSession.Mode) throws
  func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws
}
