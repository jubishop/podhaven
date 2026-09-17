// Copyright Justin Bishop, 2026

import CarPlay
import FactoryKit

@MainActor
protocol CarPlayNowPlaying: AnyObject {
  var isUpNextButtonEnabled: Bool { get set }
  var isAlbumArtistButtonEnabled: Bool { get set }
  var upNextTitle: String { get set }
  func add(_ observer: any CPNowPlayingTemplateObserver)
  func remove(_ observer: any CPNowPlayingTemplateObserver)
  func updateNowPlayingButtons(_ buttons: [CPNowPlayingButton])
}

extension CPNowPlayingTemplate: CarPlayNowPlaying {}

@MainActor
protocol CarPlaySession: AnyObject {
  var limitedUserInterfaces: CPLimitableUserInterface { get }
  var delegate: (any CPSessionConfigurationDelegate)? { get set }
}

extension CPSessionConfiguration: CarPlaySession {}

struct CarPlayListLimits {
  let items: Int
  let sections: Int
}

typealias CarPlayRateButtonFactory =
  @MainActor (@escaping @MainActor () -> Void) -> CPNowPlayingPlaybackRateButton

extension Container {
  var carPlayRateButton: Factory<CarPlayRateButtonFactory> {
    Factory(self) { { action in CPNowPlayingPlaybackRateButton { _ in action() } } }
  }

  var carPlayNowPlaying: Factory<any CarPlayNowPlaying> {
    Factory(self) { MainActor.assumeIsolated { CPNowPlayingTemplate.shared } }.scope(.cached)
  }

  var carPlaySession: Factory<@MainActor (any CPSessionConfigurationDelegate) -> any CarPlaySession>
  {
    Factory(self) { { CPSessionConfiguration(delegate: $0) } }
  }

  var carPlayListLimits: Factory<@MainActor () -> CarPlayListLimits> {
    Factory(self) {
      {
        CarPlayListLimits(
          items: CPListTemplate.maximumItemCount,
          sections: CPListTemplate.maximumSectionCount
        )
      }
    }
  }
}
